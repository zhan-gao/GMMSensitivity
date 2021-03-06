#' Compute solution path for \eqn{\ell_\infty}{l_infinity} or \eqn{\ell_1}{l1}
#' constraints
#'
#' Computes the optimal sensitivity vector at each knot of the solution path
#' that traces out the optimal bias-variance frontier when the set \eqn{C} takes
#' the form \eqn{c=B\gamma}{c=B*gamma} with the \eqn{\ell_p}{lp} norm of
#' \eqn{\gamma}{gamma} is bounded by a constant, for \eqn{p=1}, or
#' \eqn{p=\infty}{p=Inf}. This path is used as an input to
#' \code{\link{OptEstimator}}.
#'
#' The algorithm is described in Appendix A of Armstrong and Kolesár (2020)
#' @inheritParams OptEstimator
#' @param p Parameter determining which \eqn{\ell_p}{lp} norm to use, one of
#'     \code{1}, or \code{Inf}.
#' @return Optimal sensitivity matrix. Each row corresponds optimal sensitivity
#'     vector at each step in the solution path.
#' @references{
#'
#' \cite{Armstrong, T. B., and M. Kolesár (2020): Sensitivity Analysis Using
#' Approximate Moment Condition Models,
#' \url{https://arxiv.org/abs/1808.07387v4}}
#'
#' }
#' @export
lph <- function(eo, B, p=Inf) {
    if (ncol(B)==0)
        return(-eo$H %*% solve(crossprod(eo$G, solve(eo$Sig, eo$G)),
                                        t(solve(eo$Sig, eo$G))))

    ## Get orthogonalized homotopy, first B_{\perp}
    Bp <- if (nrow(B)>ncol(B)) {
              qr.Q(qr(B), complete=TRUE)[, (ncol(B)+1):nrow(B)]
          } else {
              matrix(ncol=0, nrow=nrow(B))
          }
    I <- rep(c(FALSE, TRUE), c(ncol(Bp), ncol(B)))
    Tm <- rbind(t(Bp), solve(crossprod(B), t(B)))
    Sigt <- Tm %*% eo$Sig %*% t(Tm)
    ## Get path of tilde{k}
    if (p==Inf)
        kts <- linfh0(Tm %*% eo$G, Sigt, eo$H, I)[, 1:(nrow(B)+1)]
    else
        kts <- l1h0(Tm %*% eo$G, Sigt, eo$H, I)[, 1:(nrow(B)+1)]
    ## Return sensitivity at each step. Drop lambda
    kts[, -1] %*% Tm
}

## Next step in l_infty homotopy algorithm
linfstep <- function(s, G, Sig, H, I) {
    d1 <- -s$k/s$k.d
    d1[!s$A | d1<0 | !I] <- Inf
    if(s$joined!=0)
        d1[s$joined] <- Inf

    a.d <- drop(Sig %*% s$k.d+G %*% s$mu.d)
    a <- drop(Sig %*% s$k+G %*% s$mu)

    d2 <- rep(Inf, nrow(G))
    d2[a.d>1] <- ((s$lam-a)/(a.d-1))[a.d>1]
    d2[a.d< -1] <- (-(s$lam+a)/(a.d+1))[a.d< -1]
    d2[s$A] <- Inf

    d <- min(d2, d1)
    if(d<0)
        stop("Taking a negative step")
    s$lam <- s$lam+d
    s$k <- s$k + d*s$k.d
    s$mu <- s$mu + d*s$mu.d

    if (min(d2)<min(d1)) {
        s$joined <- which(d2<=min(d2))
        s$A[s$joined] <- TRUE
    } else {
        s$A[which(d1<=min(d1))] <- FALSE
        s$joined <- 0
    }

    ## New directions
    s$s.d <- (sign(-drop(Sig %*% s$k + G %*% s$mu))*I)[s$A]
    s$mu.d <- -solve(crossprod(G[s$A, ], solve(Sig[s$A, s$A], G[s$A, ])),
                     drop(crossprod(G[s$A, ], solve(Sig[s$A, s$A], s$s.d))))
    s$k.d[s$A] <- solve(Sig[s$A, s$A], -drop(G[s$A, ] %*% s$mu.d +s$s.d))
    s$k.d[!s$A] <- 0
    s
}

## Orthogonalized homotopy solution for l_infty
## @param I vector of indicators which instruments are invalid
linfh0 <- function(G, Sig, H, I) {
    dg <- nrow(G)
    ## Initialize
    s <- list(lam=0,
              A=rep(TRUE, dg),
              mu=solve(crossprod(G, solve(Sig, G)), H),
              joined=0)
    s$k <- drop(-solve(Sig, G %*% s$mu))
    res <- matrix(c(0, s$k, s$A), nrow=1)
    colnames(res) <- c("lam", 1:dg, paste0("A", 1:dg))
    ## directions
    s$s.d <- sign(s$k) * I
    s$mu.d <- -solve(crossprod(G, solve(Sig, G)),
                     drop(crossprod(G, solve(Sig, s$s.d))))
    s$k.d <- solve(Sig, -drop(G %*% s$mu.d +s$s.d))

    while (sum(s$A) > max(sum(!I), ncol(G))) {
        s <- linfstep(s, G, Sig, H, I)
        res <- rbind(res, c(s$lam, s$k, s$A))
    }
    res
}
