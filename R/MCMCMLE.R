MCMCMLE <- function(mc.num.iterations,
                    tolerance,
                    theta,
                    seed2 ,
					          possible.stats,
					          GERGM_Object,
					          force_x_theta_updates,
					          verbose,
					          outter_iteration_number = 1,
					          stop_for_degeneracy = FALSE) {

  # get MPLE thetas
  MPLE_Results <- run_mple(GERGM_Object = GERGM_Object,
                           verbose = verbose,
                           seed2 = seed2,
                           possible.stats = possible.stats,
                           outter_iteration_number = outter_iteration_number)

  GERGM_Object <- MPLE_Results$GERGM_Object
  statistics <- MPLE_Results$statistics
  init.statistics <- MPLE_Results$init.statistics

  if (GERGM_Object@convex_hull_proportion != -1 &
      GERGM_Object@use_previous_thetas &
      outter_iteration_number > 1) {
    # skip MPLE intiialization
    temp <- theta
    theta <- list()
    theta$par <- temp
  } else {
    theta <- MPLE_Results$theta
  }

  # if we are initializing with all zeros, then reset theta to be all zeros.
  if (GERGM_Object@start_with_zeros) {
    cat("Zeroing out initial thetas becasue start_with_zeros = TRUE...\n")
    theta$par <- rep(0, length(theta))
  }

  # make sure we store the current value of theta in the GERGM object:
  GERGM_Object@theta.par <- theta$par

  # now if we are using convex_hull_proportion, then call convex hull
  # initialization.
  if (GERGM_Object@convex_hull_proportion != -1) {
    GERGM_Object <- convex_hull_initialization(GERGM_Object,
                                               seed2,
                                               possible.stats,
                                               verbose)
    theta$par <- GERGM_Object@theta.par
  }


  ##########################################################################
  ## Simulate new networks
  FIX_DEGENERACY <- FALSE
  for (i in 1:mc.num.iterations) {

    if (FIX_DEGENERACY) {
      MPLE_Results <- run_mple(GERGM_Object = GERGM_Object,
                               verbose = verbose,
                               seed2 = seed2,
                               possible.stats = possible.stats)

      GERGM_Object <- MPLE_Results$GERGM_Object
      theta <- MPLE_Results$theta
      statistics <- MPLE_Results$statistics
      init.statistics <- MPLE_Results$init.statistics
      FIX_DEGENERACY <- FALSE
    }
    GERGM_Object@theta.par <- as.numeric(theta$par)

    # now optimize the proposal variance if we are using Metropolis Hasings
    if (GERGM_Object@hyperparameter_optimization){
      if (GERGM_Object@estimation_method == "Metropolis") {
        GERGM_Object@proposal_variance <- Optimize_Proposal_Variance(
          GERGM_Object = GERGM_Object,
          seed2 = seed2,
          possible.stats = possible.stats,
          verbose = verbose,
          fine_grained_optimization = GERGM_Object@fine_grained_pv_optimization)
        cat("Proposal variance optimization complete! Proposal variance is:",
            GERGM_Object@proposal_variance,"\n",
            "--------- END HYPERPARAMETER OPTIMIZATION ---------",
            "\n\n")
      }
    }

    GERGM_Object <- Simulate_GERGM(
      GERGM_Object,
      coef = GERGM_Object@theta.par,
      seed1 = seed2,
      possible.stats = possible.stats,
      verbose = verbose,
      parallel = GERGM_Object@parallel_statistic_calculation)

    sad <- GERGM_Object@statistic_auxiliary_data
    hsn <- GERGM_Object@MCMC_output$Statistics[,sad$specified_statistic_indexes_in_full_statistics]
    hsn.tot <- GERGM_Object@MCMC_output$Statistics

    # deal with case where we only have one statistic
    if (class(hsn.tot) == "numeric") {
      hsn.tot <- matrix(hsn.tot,ncol = 1,nrow = length(hsn.tot))
      stats.data <- data.frame(Observed = init.statistics,
                               Simulated = mean(hsn.tot))
    } else {
      stats.data <- data.frame(Observed = init.statistics,
                               Simulated = colMeans(hsn.tot))
    }

    rownames(stats.data) <- GERGM_Object@full_theta_names
    cat("Simulated (averages) and observed network statistics...\n")
    print(stats.data)
    GERGM_Object <- store_console_output(GERGM_Object,toString(stats.data))
    if (verbose) {
      cat("\nOptimizing theta estimates... \n")
    }
    GERGM_Object <- store_console_output(GERGM_Object,"\nOptimizing Theta Estimates... \n")
    if (verbose) {
    theta.new <- optim(par = theta$par,
                       log.l,
                       alpha = GERGM_Object@weights,
                       hsnet = hsn,
                       ltheta = as.numeric(theta$par),
                       together = GERGM_Object@downweight_statistics_together,
                       possible.stats = possible.stats,
                       GERGM_Object = GERGM_Object,
                       method = GERGM_Object@optimization_method,
                       hessian = T,
                       control = list(fnscale = -1, trace = 6))
    } else {
      theta.new <- optim(par = theta$par,
                         log.l,
                         alpha = GERGM_Object@weights,
                         hsnet = hsn,
                         ltheta = as.numeric(theta$par),
                         together = GERGM_Object@downweight_statistics_together,
                         possible.stats = possible.stats,
                         GERGM_Object = GERGM_Object,
                         method = GERGM_Object@optimization_method,
                         hessian = T,
                         control = list(fnscale = -1, trace = 0))
    }
    if (verbose) {
      cat("\nTheta Estimates:\n")
      names(theta.new$par) <- colnames(GERGM_Object@theta.coef)
      print(theta.new$par)
    }
    GERGM_Object <- store_console_output(GERGM_Object,paste("\n", "Theta Estimates: ", paste0(theta.new$par,collapse = " "), "\n",sep = ""))

    temp <- calculate_standard_errors(hessian = theta.new$hessian,
                                      GERGM_Object = GERGM_Object)
    theta.std.errors <- temp$std_errors
    GERGM_Object <- temp$GERGM_Object
    nans <- which(is.nan(theta.std.errors))
    allow_convergence <- TRUE
    nan_stderrors <- FALSE
    if (length(nans) > 0) {
        cat("Some standard errors were not finite. Standard errors:",
            theta.std.errors,
            "This is likely due to a problem with degeneracy.")
        GERGM_Object <- store_console_output(GERGM_Object,
            paste("Some standard errors were not finite. Standard errors:",
            theta.std.errors,
            "This is likely due to a problem with degeneracy."))
        allow_convergence <- FALSE
        nan_stderrors <- TRUE
    } else {
        # theta.std.errors <- 1 / sqrt(abs(diag(theta.new$hessian)))
        # Calculate the p-value based on a z-test of differences
        # The tolerance is the alpha at which differences are significant
        p.value <- rep(0,length(as.numeric(theta$par)))
        count <- rep(0, length(as.numeric(theta$par)))
        for (j in 1:length(theta$par)) {
            #two sided z test
            p.value[j] <- 2*pnorm(-abs((as.numeric(theta.new$par)[j] -
              as.numeric(theta$par)[j])/theta.std.errors[j]))
            #abs(theta.new$par[i] - theta$par[i]) > bounds[i]
            #if we reject any of the tests then convergence has not been reached!
            if (p.value[j] < tolerance) {count[j] = 1}
        }
        if (verbose) {
            cat("\np.values for two-sided z-test of difference between current and updated theta estimates:\n\n")
        }
        GERGM_Object <- store_console_output(GERGM_Object,"\np.values for two-sided z-test of difference between current and updated theta estimates:\n\n")
        if (verbose) {
          names(p.value) <- colnames(GERGM_Object@theta.coef)
          print(round(p.value))
            cat("\n")
        }
        GERGM_Object <- store_console_output(GERGM_Object,paste(p.value, "\n \n"))

        if (GERGM_Object@using_slackr_integration) {
          time <- Sys.time()
          message <- paste("Theta parameter estimate convergence p-values,",
                           "at:",toString(time))
          p_values <- paste(round(p.value,3))
          slackr::slackr_bot(
            message,
            p_values,
            channel = GERGM_Object@slackr_integration_list$channel,
            username = GERGM_Object@slackr_integration_list$model_name,
            incoming_webhook_url = GERGM_Object@slackr_integration_list$incoming_webhook_url)
        }
    }


    # calculate MCMC chain convergence diagnostic
    geweke_stat <- as.numeric(coda::geweke.diag(hsn.tot$edges)$z)
    cat("MCMC convergence Geweke test statistic:",geweke_stat,
        "\n(If the absolute value is greater than 1.7, increase MCMC_burnin)\n")
    GERGM_Object <- store_console_output(GERGM_Object,
      paste("MCMC convergence Geweke test statistic:",geweke_stat,
      "\n(If the absolute value is greater than 1.7, increase MCMC_burnin)\n"))

    if(!is.finite(geweke_stat)) {

    }


    # see if the parameter values hav increased more than four orders of
    # magnitude over the past values.

    # creates a logical
    degen <- max(abs(theta.new$par)) > 10000 * max(abs(theta$par))
    # if either or both are TRUE, then we need to fix things.
    if ((nan_stderrors | degen)| (degen & nan_stderrors)) {
      # hard stop if we have set the stop_for_degeneracy parameter
      if (stop_for_degeneracy) {
        # push to slack if desired
        if (GERGM_Object@using_slackr_integration) {
          time <- Sys.time()
          message <- paste("Theta parameter estimates have diverged,",
                           "stopping at:",toString(time))
          slackr::slackr_bot(
            message,
            channel = GERGM_Object@slackr_integration_list$channel,
            username = GERGM_Object@slackr_integration_list$model_name,
            incoming_webhook_url = GERGM_Object@slackr_integration_list$incoming_webhook_url)
        }
        stop("Theta parameter estimates have diverged, please respecify model!")
      }
      if (GERGM_Object@hyperparameter_optimization) {
        message("Parameter estimates appear to have become degenerate, attempting to fix the problem...")
        GERGM_Object <- store_console_output(GERGM_Object,"Parameter estimates appear to have become degenerate, attempting to fix the problem...")

        if (GERGM_Object@using_slackr_integration) {
          time <- Sys.time()
          message <- paste("Theta parameter estimates have diverged,",
                           "attempting to fix the problem at:",toString(time))
          slackr::slackr_bot(
            message,
            channel = GERGM_Object@slackr_integration_list$channel,
            username = GERGM_Object@slackr_integration_list$model_name,
            incoming_webhook_url = GERGM_Object@slackr_integration_list$incoming_webhook_url)
        }

        # do not allow convergence
        allow_convergence <- FALSE
        # If we are using Metropolis Hastings, then try reducing weights and
        # upping the gain factor
        if (GERGM_Object@estimation_method == "Metropolis") {
          GERGM_Object@weights <- GERGM_Object@weights - 0.1
          cat("Reducing exponential weights by 0.1 to:",
              GERGM_Object@weights,
              "in an attempt to address degeneracy issue...\n")
          GERGM_Object <- store_console_output(GERGM_Object,paste(
            "Reducing exponential weights by 0.1 to:",
            GERGM_Object@weights,
            "in an attempt to address degeneracy issue..."))

          if (GERGM_Object@MPLE_gain_factor == 0) {
            GERGM_Object@MPLE_gain_factor <- 0.05
          } else {
            GERGM_Object@MPLE_gain_factor <-  GERGM_Object@MPLE_gain_factor + 0.05
          }
          cat("Increasing MPLE gain factor by 0.05 to:",
              GERGM_Object@MPLE_gain_factor,
              "as exponential weights have decreased...\n")
          GERGM_Object <- store_console_output(GERGM_Object,paste(
            "Increasing MPLE gain factor by 0.05 to:",
            GERGM_Object@MPLE_gain_factor,
            "as exponential weights have decreased..."))
          # re-estimate thetas with more downweighting
          FIX_DEGENERACY <- TRUE
        }
        # additionally, try doubling the burin and the number of MCMC iterations.
        old_nsim <- GERGM_Object@number_of_simulations
        old_burinin <- GERGM_Object@burnin
        new_nsim <- 2 * old_nsim
        new_burnin <- 2 * old_burinin
        GERGM_Object@number_of_simulations <- new_nsim
        GERGM_Object@burnin <- new_burnin
        old_thin <- GERGM_Object@thin
        GERGM_Object@thin <- old_thin/2
        cat("Doubling burnin from:", old_burinin, "to", new_burnin,
            "and number of networks simulated from:", old_nsim, "to", new_nsim,
            "in an attempt to address degeneracy issue...\n")
        GERGM_Object <- store_console_output(GERGM_Object,paste(
          "Doubling burnin from:", old_burinin, "to", new_burnin,
          "and number of networks simulated from:", old_nsim, "to", new_nsim,
          "in an attempt to address degeneracy issue..."))
      }else{
        message("Parameter estimates appear to have become degenerate, returning previous thetas. Model output should not be trusted. Try specifying a larger number of simulations or a different parameterization.")
        GERGM_Object <- store_console_output(GERGM_Object,"Parameter estimates appear to have become degenerate, returning previous thetas. Model output should not be trusted. Try specifying a larger number of simulations or a different parameterization.")
        return(list(theta.new,GERGM_Object))
      }
    } else if (!is.finite(geweke_stat)) {
      old_nsim <- GERGM_Object@number_of_simulations
      old_burinin <- GERGM_Object@burnin
      new_nsim <- 2 * old_nsim
      new_burnin <- 2 * old_burinin
      GERGM_Object@number_of_simulations <- new_nsim
      GERGM_Object@burnin <- new_burnin
      old_thin <- GERGM_Object@thin
      GERGM_Object@thin <- old_thin/2
      GERGM_Object@proposal_variance <- GERGM_Object@proposal_variance/10
      cat("MH acceptance rate was zero. Reducing proposal_variance by an order",
          "of magnitude to:",GERGM_Object@proposal_variance,"\n")
      GERGM_Object <- store_console_output(GERGM_Object,paste(
        "MH acceptance rate was zero. Reducing proposal_variance by an order",
        "of magnitude to:",GERGM_Object@proposal_variance))
      cat("Doubling burnin from:", old_burinin, "to", new_burnin,
          "and number of networks simulated from:", old_nsim, "to", new_nsim,
          "in an attempt to address degeneracy issue...\n")
      GERGM_Object <- store_console_output(GERGM_Object,paste(
        "Doubling burnin from:", old_burinin, "to", new_burnin,
        "and number of networks simulated from:", old_nsim, "to", new_nsim,
        "in an attempt to address degeneracy issue..."))

      # do not allow convergence
      allow_convergence <- FALSE
    } else if (abs(geweke_stat) > 1.7){
      # if model was not degenerate but Geweke statistics say it did not converge
      # double number of iterations and burnin automatically.
      if (GERGM_Object@hyperparameter_optimization){
        old_nsim <- GERGM_Object@number_of_simulations
        old_burinin <- GERGM_Object@burnin
        new_nsim <- 2 * old_nsim
        new_burnin <- 2 * old_burinin
        GERGM_Object@number_of_simulations <- new_nsim
        GERGM_Object@burnin <- new_burnin
        old_thin <- GERGM_Object@thin
        GERGM_Object@thin <- old_thin/2
        cat("Doubling burnin from:", old_burinin, "to", new_burnin,
            "and number of networks simulated from:", old_nsim, "to", new_nsim,
            "in an attempt to address degeneracy issue...\n")
        GERGM_Object <- store_console_output(GERGM_Object,paste(
          "Doubling burnin from:", old_burinin, "to", new_burnin,
          "and number of networks simulated from:", old_nsim, "to", new_nsim,
          "in an attempt to address degeneracy issue..."))
        # do not allow convergence
        allow_convergence <- FALSE
      }
    }



    # check to see if we had a zero percent accept rate if using MH, and if so,
    # then adjust proposal variance and try again -- do not signal convergence.
    if (GERGM_Object@estimation_method == "Metropolis") {
      if (GERGM_Object@MCMC_output$Acceptance.rate == 0){
        old <- GERGM_Object@proposal_variance
        new <- old/2
        cat("Acceptance rate was zero, decreasing proposal variance from",old,
            "to",new,"and simulating a new set of networks...\n")
        GERGM_Object@proposal_variance <- new
        allow_convergence <- FALSE
      }
    }
    if (allow_convergence) {
      if (sum(count) == 0){
        #conditional to check and see if we are requiring more updates
        if(i >= force_x_theta_updates){
          if(verbose){
            message("Theta parameter estimates have converged...")
          }
          GERGM_Object <- store_console_output(GERGM_Object,
                            "Theta parameter estimates have converged...")
          GERGM_Object@theta_estimation_converged <- TRUE
          theta <- theta.new
          GERGM_Object@theta.par <- as.numeric(theta$par)
          return(list(theta.new,GERGM_Object))
        }else{
          if(verbose){
            message(paste("Forcing",force_x_theta_updates,
                          "iterations of theta updates..."),sep = " ")
          }
          GERGM_Object <- store_console_output(GERGM_Object,paste("Forcing",
                            force_x_theta_updates,
                            "iterations of theta updates..."))
        }
      }
      # only updat parameter estimates if we had an acceptance rate greater than zero
      theta <- theta.new
      GERGM_Object@theta.par <- as.numeric(theta$par)
    }
  } #loop over MCMC outer iterations
  return(list(theta.new,GERGM_Object))
}
