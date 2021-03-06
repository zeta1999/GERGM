% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/Convert_Simulated_Networks_To_Observed_Scale.R
\name{convert_simulated_networks_to_observed_scale}
\alias{convert_simulated_networks_to_observed_scale}
\title{Transforms simulated networks to observed scale. In general, do not use this function.}
\usage{
convert_simulated_networks_to_observed_scale(GERGM_Object)
}
\arguments{
\item{GERGM_Object}{A GERGM object returned by the `gergm()` function. In
general, this function should not be used except in the case where you are
working with a GERGM object where the `@MCMC_output$Networks` field is still
on the [0,1] unconstrained space, and you wish to transform it to the
observed scale.}
}
\value{
A GERGM Object
}
\description{
Transforms simulated networks to observed scale. In general, do not use this function.
}
