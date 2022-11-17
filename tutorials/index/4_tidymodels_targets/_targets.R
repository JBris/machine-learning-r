library(targets)

source("R/define_sw_recipe.R")

tar_option_set(packages = c(
  "carrier", 
  "DataExplorer",
  "knitr",
  "mlflow",
  "reticulate",
  "tidyverse", 
  "tidymodels"
)
)

list(
  tar_target(MLFLOW_URL, "http://mlflow:5000"),
  tar_target(conda_active, use_condaenv("r-mlflow-1.30.0")),
  tar_target(mlflow_uri, mlflow::mlflow_set_tracking_uri(MLFLOW_URL)),
  tar_target(data, load_sw_data()),
  tar_target(data_split, initial_split(data, prop = 0.8)),
  tar_target(data_train, training(data_split)),
  tar_target(data_test, testing(data_split)),
  tar_target(sw_recipe, preprocess_data_recipe(data_train)),
  tar_target(sw_model, get_rf()),
  tar_target(sw_workflow, define_workflow(sw_recipe, sw_model)),
  tar_target(tree_grid, seq(50, 200, by = 50)),
  tar_target(sw_grid, expand_grid(trees = tree_grid)),
  tar_target(
    sw_grid_results,
    tune_grid(sw_workflow, resamples = vfold_cv(data_train, v = 5), grid = sw_grid)
  ),
  tar_target(
    hyperparameters, 
    select_by_pct_loss(sw_grid_results, metric = "rmse", limit = 5, trees)
  ),
  tar_target(client, mlflow_client()),
  tar_target(s3_bucket, "s3://mlflow/sw_rf"),
  tar_target(experiment, mlflow_set_experiment(experiment_name = "sw_rf", artifact_location = s3_bucket)),
  tar_target(experiment_id, mlflow_get_experiment(name = "sw_rf", client = client)$experiment_id),
  tar_target(run, mlflow_start_run(client = client, experiment_id = experiment_id)),
  tar_target(sw_rf, train_rf(data_train, sw_workflow, hyperparameters, client, run)),
  tar_target(packaged_sw_rf, package_rf(sw_rf)),
  tar_target(metrics, get_metrics(sw_rf, data_test, client, run)),
  tar_target(pred_actual, load_pred_actual(sw_rf, data_test, client, run)),
  tar_target(crated_model, "/tmp/sw_rf"),
  tar_target(saved_model, mlflow_save_model(packaged_sw_rf, crated_model)),
  tar_target(logged_model, mlflow_log_artifact(crated_model, client = client, 
                                               run_id =  run$run_uuid)),
  tar_target(versioned_model, mlflow_create_model_version("sw_rf", run$artifact_uri, 
                                                          run_id = run$run_uuid,
                                                          client = client)),
  tar_target(sw_report, generate_sw_report(data, client, run)),
  tar_target(sw_plot, plot_sw(data, client, run)),
  tar_target(data_csv, "/tmp/star_wars_characters.csv"),
  tar_target(written_csv, write_csv(data, data_csv)),
  tar_target(logged_csv, mlflow_log_artifact(data_csv, 
                                             client = client, run_id =  run$run_uuid)
  ),
  tar_target(run_end, mlflow_end_run(run_id =  run$run_uuid, client = client))
)