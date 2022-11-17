# Imports

library(carrier)
library(DataExplorer)
library(knitr)
library(reticulate)
library(mlflow)
library(targets)
library(tidymodels)
library(tidyverse)

# Functions

load_sw_data = function() {
  dplyr::starwars |>
    select(c(height, mass)) |>
    mutate_if(is.numeric, ~ replace_na(.,0))
}

preprocess_data_recipe = function(data_train) {
  recipe(data_train) |>
    update_role(everything(), new_role = "support") |> 
    update_role(height, new_role = "outcome") |>
    update_role(mass, new_role = "predictor") |>
    step_impute_mean(mass) |>
    step_normalize(all_numeric(), -all_outcomes())
}

get_rf = function() {
  rand_forest(trees = tune()) |>
    set_engine("ranger") |>
    set_mode("regression")
}

define_workflow = function(sw_recipe, sw_model) {
  workflows::workflow() |>
    add_recipe(sw_recipe) |>
    add_model(sw_model)
}

log_workflow_parameters = function(workflow, client, run) {
  spec = workflows::extract_spec_parsnip(workflow)
  parameter_names = names(spec$args)
  parameter_values = lapply(spec$args, rlang::get_expr)
  for(i in seq_along(spec$args)) {
    parameter_name = parameter_names[[i]]
    parameter_value = parameter_values[[i]]
    if (!is.null(parameter_value)) {
      mlflow_log_param(parameter_name, parameter_value, client = client, run_id = run$run_uuid)
    }
  }
  workflow
}

log_metrics = function(metrics, estimator = "standard", client, run) {
  metrics |> 
    filter(.estimator == estimator) |>
    pmap(
      function(.metric, .estimator, .estimate) {
        mlflow_log_metric(.metric, .estimate, client = client, run_id = run$run_uuid)  
      }
    )
  metrics
}

train_rf = function(data_train, sw_workflow, hyperparameters, client, run) {
  sw_workflow |>
    finalize_workflow(hyperparameters) |>
    log_workflow_parameters(client = client, run = run) |> 
    fit(data_train)
}

package_rf = function(sw_rf) {
  carrier::crate(
    function(x) workflows:::predict.workflow(sw_rf, x),
    sw_rf = sw_rf
  )
}

get_metrics = function(sw_rf, data_test, client, run) {
  sw_rf |>
    predict(data_test) |>
    metric_set(rmse, mae, rsq)(data_test$height, .pred) |> 
    log_metrics(client = client, run = run)
}

load_pred_actual = function(sw_rf, data_test, client, run) {
  sw_rf |>
    predict(new_data = data_test) |>
    (function(x) x$.pred)() |>
    iwalk(
      ~ mlflow_log_metric("prediction", .x, step = as.numeric(.y), 
                          client = client, run_id = run$run_uuid)
    )
  
  data_test$height |> 
    iwalk(
      ~ mlflow_log_metric("actual",  .x, step = .y, 
                          client = client, run_id = run$run_uuid)
    )
}

generate_sw_report = function(data, client, run) {
  data |>
    select_if(~ !is.list(.x)) |>
    create_report(output_file = "star_wars.html", output_dir = "/tmp", 
                  report_title = "Star Wars Report", quiet = T) 
  logged_report = mlflow_log_artifact("/tmp/star_wars.html", 
                                      client = client, run_id =  run$run_uuid) 
}

plot_sw = function(data, client, run) {
  sw_plot = "/tmp/star_wars_characters.png"
  png(filename = sw_plot)
  plot(data$height, data$mass)
  doff = dev.off()
  logged_plot = mlflow_log_artifact(sw_plot, client = client, run_id =  run$run_uuid) 
}