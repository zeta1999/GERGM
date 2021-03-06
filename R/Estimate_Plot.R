#' Generate parameter estimate plot with 95 percent CI's from a GERGM object.
#'
#' @param GERGM_Object The object returned by the estimation procedure using the
#' GERGM function.
#' @param normalize_coefficients Defaults to FALSE, if TRUE then parameter
#' estimates will be converted be divided by their standard deviations with
#' and displayed with 95 percent confidence intervals. These coefficients will
#' no longer be comparable, but make graphical interpretation of significance
#' and sign easier.
#' @param coefficients_to_plot An optional argument indicating which kind of
#' parameters to plot. Can be one of "both","covariate", or "structural". Useful
#' for creating separate parameter plots for covariates and structural
#' parameters when these parameters are on very different scales.
#' @param coefficient_names Defaults to NULL. Can be a string vector of names
#' for coefficients to be used in making publication quality plots.
#' @param leave_out_coefficients Defaults to NULL. Can be a string vector of
#' coefficient names as they appear in the plot. These coefficients will be
#' removed from the final plot. Useful if the intercept term is much larger in
#' magnitude than other estimates, and the user wishes to clarify the other
#' parameter estimates without normalizing.
#' given
#' @param comparison_model A GERGM_Object produced by an alternative model whose
#' parameter estimates are to be compared to the existing model. Defaults to
#' NULL.
#' @param model_names If a comparison_model is provided, then each model must be
#' given a name via the model_names parameter. Defaults to NULL.
#' @param text_size The base size for axis text. Defaults to 12.
#' @return A parameter estimate plot.
#' @export
Estimate_Plot <- function(
  GERGM_Object,
  normalize_coefficients = FALSE,
  coefficients_to_plot = c("both","covariate","structural"),
  coefficient_names = NULL,
  leave_out_coefficients = NULL,
  comparison_model = NULL,
  model_names = NULL,
  text_size = 12
  ){

  coefficients_to_plot <- coefficients_to_plot[1]

  using_comparsion_model <- FALSE
  if (!is.null(comparison_model)) {
    using_comparsion_model <- TRUE
  }

  #define colors
  UMASS_BLUE <- rgb(51,51,153,255,maxColorValue = 255)
  UMASS_RED <- rgb(153,0,51,255,maxColorValue = 255)
  UMASS_GREEN <- rgb(0,102,102,195,maxColorValue = 255)

  Model <- Variable <- Coefficient <- SE <- Coefficient_Type <- NULL

  # if we are only using the one model, proceed as normal.
  if (!using_comparsion_model) {
    data <- prepare_parameter_estimate_data(GERGM_Object,
                                            normalize_coefficients,
                                            coefficients_to_plot,
                                            coefficient_names,
                                            leave_out_coefficients,
                                            "Model 1")
    data$Variable <- factor(data$Variable , levels = rev(data$Variable))
    # Plot
    if (length(GERGM_Object@lambda.coef[,1]) > 0 &
        coefficients_to_plot == "covariate") {
      zp1 <- ggplot2::ggplot(data, ggplot2::aes(colour = Coefficient_Type)) +
        ggplot2::scale_color_manual(values = c(UMASS_BLUE,UMASS_RED,UMASS_GREEN)) +
        ggplot2::theme(axis.text = ggplot2::element_text(size = text_size))
    } else if (length(GERGM_Object@lambda.coef[,1]) > 0 &
                coefficients_to_plot == "both") {
      zp1 <- ggplot2::ggplot(data, ggplot2::aes(colour = Coefficient_Type)) +
        ggplot2::scale_color_manual(values = c(UMASS_BLUE,UMASS_RED,UMASS_GREEN)) +
        ggplot2::theme(axis.text = ggplot2::element_text(size = text_size,
          angle = 90, hjust = 1)) +
        ggplot2::coord_flip()
        # ggplot2::facet_grid(~ Coefficient_Type,
        #                     scales = "free",
        #                     space = "free_x")
        # ggplot2::facet_wrap(~ Coefficient_Type, ncol = 1)
    } else {
      zp1 <- ggplot2::ggplot(data, ggplot2::aes(colour = Coefficient_Type)) +
        ggplot2::scale_color_manual(values = UMASS_BLUE) +
        ggplot2::theme(axis.text = ggplot2::element_text(size = text_size))
    }
    zp1 <- zp1 + ggplot2::geom_hline(yintercept = 0,
                                     colour = gray(1/2),
                                     lty = 2)
    zp1 <- zp1 + ggplot2::geom_linerange( ggplot2::aes(x = Variable,
        ymin = Coefficient - SE*(-qnorm((1 - 0.9)/2)),
        ymax = Coefficient + SE*(-qnorm((1 - 0.9)/2))),
        lwd = 1,
        position = ggplot2::position_dodge(width = 1/2))
    zp1 <- zp1 + ggplot2::geom_pointrange(ggplot2::aes(x = Variable,
        y = Coefficient,
        ymin = Coefficient - SE*(-qnorm((1 - 0.95)/2)),
        ymax = Coefficient + SE*(-qnorm((1 - 0.95)/2))),
        lwd = 1/2,
        position = ggplot2::position_dodge(width = 1/2),
        shape = 21, fill = "WHITE")
    if(normalize_coefficients){
      zp1 <- zp1  + ggplot2::theme_bw() +
        ggplot2::coord_flip() +
        ggplot2::theme(legend.position = "none") +
        ggplot2::ylab("Normalized Coefficient")
    }else{
      if (length(GERGM_Object@lambda.coef[,1]) > 0 &
          coefficients_to_plot == "both") {
        zp1 <- zp1  + ggplot2::theme_bw() +
          ggplot2::theme(legend.position = "none",
                         axis.text = ggplot2::element_text(size = text_size),
                         strip.background = ggplot2::element_blank(),
                         strip.text = ggplot2::element_blank())
      } else {
        zp1 <- zp1  + ggplot2::theme_bw() +
          ggplot2::coord_flip() +
          ggplot2::theme(legend.position = "none")
      }
    }
    print(zp1)


  } else {
    # if comparison data was provided
    data1 <- prepare_parameter_estimate_data(GERGM_Object,
                                            normalize_coefficients,
                                            coefficients_to_plot,
                                            coefficient_names,
                                            leave_out_coefficients,
                                            model_names[1])
    data2 <- prepare_parameter_estimate_data(comparison_model,
                                             normalize_coefficients,
                                             coefficients_to_plot,
                                             coefficient_names,
                                             leave_out_coefficients,
                                             model_names[2])

    data <- rbind(data1, data2)
    data$Variable <- factor(data$Variable , levels = rev(data$Variable))
    print(data)
    # Plot

    zp1 <- ggplot2::ggplot(data, ggplot2::aes(colour = Model)) +
        ggplot2::scale_color_manual(values = c(UMASS_BLUE,UMASS_RED,UMASS_GREEN)) +
      ggplot2::theme(axis.text = ggplot2::element_text(size = text_size))

    zp1 <- zp1 + ggplot2::geom_hline(yintercept = 0,
                                     colour = gray(1/2),
                                     lty = 2)
    zp1 <- zp1 + ggplot2::geom_linerange( ggplot2::aes(x = Variable,
      ymin = Coefficient - SE*(-qnorm((1 - 0.9)/2)),
      ymax = Coefficient + SE*(-qnorm((1 - 0.9)/2))),
      lwd = 1,
      position = ggplot2::position_dodge(width = 1/2))
    zp1 <- zp1 + ggplot2::geom_pointrange(ggplot2::aes(x = Variable,
      y = Coefficient,
      ymin = Coefficient - SE*(-qnorm((1 - 0.95)/2)),
      ymax = Coefficient + SE*(-qnorm((1 - 0.95)/2))),
      lwd = 1/2,
      position = ggplot2::position_dodge(width = 1/2),
      shape = 21, fill = "WHITE")
    if(normalize_coefficients){
      zp1 <- zp1  + ggplot2::theme_bw() +
        ggplot2::coord_flip() +
        ggplot2::theme(legend.position = "none") +
        ggplot2::ylab("Normalized Coefficient")
    }else{
      zp1 <- zp1  + ggplot2::theme_bw() +
        ggplot2::theme(legend.direction = 'horizontal',
                       legend.position = "top",
                       legend.title = ggplot2::element_blank()) +
        ggplot2::coord_flip()

    }
    print(zp1)
  }


}
