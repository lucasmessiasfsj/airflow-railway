# DAGs shipped with the template

Everything in this directory is baked into the image as the `dags-folder`
bundle, so a fresh deployment has real pipelines to run rather than an empty
grid. Replace them with your own — either by committing to this directory and
letting Railway rebuild, or by setting `AIRFLOW_DAGS_GIT_REPO_URL` on every
Airflow service to add your own git repository as a second bundle.
