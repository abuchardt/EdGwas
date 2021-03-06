#' Cross-validation for edgwas
#'
#' Does k-fold cross-validation for edgwas, produces multiple plots, and returns a value for rho.
#'
#' @param x Input matrix, of dimension nobs x nvars; each row is an observation vector. A matrix of polygenic scores (PSs) with nvars = nouts. Can be in sparse matrix format.
#' @param y Quantitative response matrix, of dimension nobs x nouts.
#' @param rho (Non-negative) optional user-supplied rho sequence; default is \code{NULL}, and EdGwas chooses its own sequence.
#' @param nfolds Number of folds - default is 10. Although nfolds can be as large as the sample size (leave-one-out CV), it is not recommended for large datasets. Smallest value allowable is \code{nfolds = 3}.
#' @param type.measure Loss to use for cross-validation. Currently two options; the default is \code{type.measure="mse"}, which uses the mean-squared error. \code{type.measure = "mae"} gives the mean absolute error.
#' @param nrho The number of rho values. Default is 40.
#' @param logrho Logical flag for log transformation of the rho sequence. Default is \code{logrho = FALSE}.
#' @param rho.min.ratio Smallest value for rho, as a fraction of rho.max, the (data derived) entry value (i.e. the smallest value for which all coefficients are zero) - default is 10e-04.
#'
#' @details The function runs edgwas nfolds+1 times; the first to get the rho sequence, and then the remainder to compute the fit with each of the folds omitted. The error is accumulated, and the average error and standard deviation over the folds is computed. Note that the results of cv.edgwas are random, since the folds are selected at random. Users can reduce this randomness by running cv.edgwas many times, and averaging the error curves.
#'
#' @return An object of class "cv.edgwas" is returned, which is a list with results of the cross-validation fit. \item{rho}{The values of rho used in the fits.} \item{cvm}{The mean cross-validated error - a vector of length length(rho).} \item{cvsd}{ The estimate of the standard error of cvm.} \item{cvup}{Upper curve = cvm + cvsd.} \item{cvlo}{Lower curve = cvm - cvsd.} \item{name}{A text string indicating type of measure (for plotting purposes).} \item{rho.min}{Value of rho that gives minimum cvm.} \item{rho.1se}{Smallest value of lambda such that the error is within 1 standard error of the minimum.} \item{edgwas.fit}{A fitted edgwas object for the full data.}
#'
#' @examples
#' N <- 1000 #
#' q <- 10 #
#' p <- 1000 #
#' set.seed(1)
#' # Sample 1
#' x0 <- matrix(rbinom(n = N*p, size = 2, prob = 0.3), nrow=N, ncol=p)
#' B <- matrix(0, nrow = p, ncol = q)
#' B[1, 1:2] <- 2.5
#' y0 <- x0 %*% B + matrix(rnorm(N*q), nrow = N, ncol = q)
#' beta <- ps.edgwas(x0, y0)$beta
#' # Sample 2
#' x <- matrix(rbinom(n = N*p, size = 2, prob = 0.3), nrow=N, ncol=p)
#' y <- x %*% B + matrix(rnorm(N*q), nrow = N, ncol = q)
#' ps <- x %*% beta
#' ###
#' pc <- cv.edgwas(ps, y)
#' \dontrun{
#' plot(pc, 1)
#' plot(pc, 1, zoom = 10)
#' plot(pc, 2)
#' }
#'
#' @export
#'
cv.edgwas <- function(x, y, rho = NULL, nfolds = 10,
                      type.measure = c("mse", "mae"),
                      nrho = ifelse(is.null(rho), 40, length(rho)), logrho = FALSE,
                      rho.min.ratio = 10e-04) {

  if (!is.null(rho) && length(rho) < 2)
    stop("Need more than one value of rho for cv.edgwas")

  if (missing(type.measure))
    type.measure = "mse"
  else type.measure = match.arg(type.measure)

  edgwas.call <- match.call(expand.dots = TRUE)
  edgwas.call[[1]] <- as.name("edgwas")
  edgwas.object <- edgwas(x, y, rho, nrho, logrho, rho.min.ratio)
  edgwas.object$call <- edgwas.call

  if (nfolds < 3)
    stop("nfolds must be bigger than 3; nfolds=10 recommended")

  rho <- edgwas.object$rho
  PS <- edgwas.object$PS
  P <- edgwas.object$P

  foldid <- sample(rep(seq(nfolds), length = nrow(y)))
  outlist = vector(mode = "list", length = nfolds)
  for (i in seq(nfolds)) {
    fold <- foldid == i

    yTrain <- y[!fold, ]
    xTrain <- PS[!fold, ]

    outlist[[i]] <- edgwas(x = xTrain, y = yTrain,
                           rho = rho)
  }

  cvstuff <- cvcompute(outlist, rho = rho, PS = PS, y = y, nfolds = nfolds,
                       P = P, type.measure = type.measure,
                       logrho = logrho,
                       rho.min.ratio = rho.min.ratio)
  cvm <- cvstuff$cvm
  cvsd <- cvstuff$cvsd
  cvname <- names(cvstuff$type.measure)

  rhoMin <- rho[which.min(cvm)]
  idx <- max(which(rev(cvm[seq(which.min(cvm))]) < cvm[which.min(cvm)] + cvsd[which.min(cvm)]))
  rho1se <- rev(rho[seq(which.min(cvm))])[idx]

  out <- list(rho = rho, cvm = cvm, cvsd = cvsd,
              cvup = cvm + cvsd,
              cvlo = cvm - cvsd,
              name = cvname,
              rho.min = rhoMin,
              rho.1se = rho1se,
              edgwas.fit = edgwas.object)
  class(out) <- "cv.edgwas"
  out
}


#' Internal EdGwas functions.
#'
#' @details These are not intended for use by users but may of interest to developers. cvcompute does cross-validation.
#'
#' @keywords internal
#'
# Cross-validation
cvcompute <- function(outlist, rho, PS, y, nfolds, P,
                      type.measure,
                      logrho, rho.min.ratio) {

  nrho <- length(rho)
  foldid <- sample(rep(seq(nfolds), length = nrow(y)))

  cvraw <- vector(mode = "list", length = nrho)
  cvraw <- lapply(cvraw, FUN = function(l) matrix(NA, nrow(y), ncol(y)))
  cvmFold <- vector(mode = "list", length = nrho)
  cvmFold <- lapply(cvmFold, FUN = function(l) matrix(NA, nfolds, ncol(y)))

  for (i in 1:nfolds) {

    fold <- foldid == i

    predsList <- predict(outlist[[i]], newPS = PS[fold, ], type = "link")

    for (j in seq(nrho)) {

      # Rotate Y (to obtain independence)
      w <- expm::sqrtm(outlist[[i]]$P[[j]]) ## qxq
      yTestIn <- y[fold, ] %*% w

      for (l in seq(ncol(y))) {

        # Compute prediction error
        preds <- predsList[[j]][, l]
        cvraw[[j]][fold, l] <- switch(type.measure,
                                      mse = (preds - yTestIn[, l])^2,
                                      mae = abs(preds - yTestIn[, l]))

      }

      cvmFold[[j]][i,] <- apply(cvraw[[j]][fold, ], 2, mean, na.rm = TRUE)

    }
  }

  N <- nrow(y)
  q <- ncol(y)

  cvm <- sapply(cvraw, mean, na.rm = TRUE)
  cvsd <- sqrt(sapply(seq_along(cvmFold), FUN = function(j) sum((cvmFold[[j]] - cvm[j])^2, na.rm = TRUE))/(q*N-1))

  names(type.measure) <- type.measure


  list(cvm = cvm, cvsd = cvsd, type.measure = type.measure)

}
