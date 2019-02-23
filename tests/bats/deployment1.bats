#!/usr/bin/env bats
#
# Test runner for deployment tests.
#

load test_helper
load test_helper_drupaldev
load test_helper_drupaldev_deployment

@test "Deployment; Acquia integration" {
  # Source directory for initialised codebase.
  # If not provided - directory will be created and a site will be initialised.
  # This is to facilitate local testing.
  SRC_DIR="${SRC_DIR:-}"

  # "Remote" repository to deploy the artefact to. It is located in the host
  # filesystem and just treated as a remote for currently installed codebase.
  REMOTE_REPO_DIR=${REMOTE_REPO_DIR:-${BUILD_DIR}/deployment_remote}

  step "Starting DEPLOYMENT tests"

  if [ ! "${SRC_DIR}" ]; then
    SRC_DIR="${BUILD_DIR}/deployment_src"
    step "Deployment source directory is not provided - using directory ${SRC_DIR}"
    prepare_fixture_dir "${SRC_DIR}"

    # Enable Acquia integration for this test to run independent deployment.
    export DRUPALDEV_OPT_PRESERVE_ACQUIA=Y

    step "Create .env.local file with Acquia credentials"
    {
      echo AC_API_USER_NAME="dummy";
      echo AC_API_USER_PASS="dummy";
    } >> "${CURRENT_PROJECT_DIR}"/.env.local

    # Override download from Acquia with a special flag. This still allows to
    # validate that download script expects credentials, but does not actually
    # run the download (it would fail since there is no Acquia environment
    # attached to this test).
    # A DEMO_DB_TEST database will be used as actual database to provision site.
    echo "DB_DOWNLOAD_PROCEED=0" >> "${CURRENT_PROJECT_DIR}"/.env.local

    # We need to use "current" directory as a place where the deployment script
    # is going to run from, while "SRC_DIR" is a place where files are taken
    # from for deployment. They may be the same place, but we are testing them
    # if they are separate, because most likely SRC_DIR will contain code
    # built on previous build stages.
    provision_site "${CURRENT_PROJECT_DIR}"

    assert_files_present_common "${CURRENT_PROJECT_DIR}"
    assert_files_present_deployment  "${CURRENT_PROJECT_DIR}"
    assert_files_present_integration_acquia  "${CURRENT_PROJECT_DIR}"
    assert_files_present_integration_lagoon  "${CURRENT_PROJECT_DIR}"
    assert_files_present_no_integration_ftp  "${CURRENT_PROJECT_DIR}"

    step "Copying built codebase into code source directory ${SRC_DIR}"
    cp -R "${CURRENT_PROJECT_DIR}/." "${SRC_DIR}/"
  else
    step "Using provided SRC_DIR ${SRC_DIR}"
    assert_dir_not_empty "${SRC_DIR}"
  fi

  # Make sure that all files were copied out from the container or passed from
  # the previous stage of the build.
  assert_files_present_common "${SRC_DIR}"
  assert_files_present_deployment "${SRC_DIR}"
  assert_files_present_integration_acquia "${SRC_DIR}"
  assert_files_present_integration_lagoon "${SRC_DIR}"
  assert_files_present_no_integration_ftp "${SRC_DIR}"
  assert_git_repo "${SRC_DIR}"

  # Make sure that one of the excluded directories will be ignored in the
  # deployment artifact.
  mkdir -p "${SRC_DIR}"/node_modules
  touch "${SRC_DIR}"/node_modules/test.txt

  step "Preparing remote repo directory ${REMOTE_REPO_DIR}"
  prepare_fixture_dir "${REMOTE_REPO_DIR}"
  git_init "${REMOTE_REPO_DIR}" 1

  pushd "${CURRENT_PROJECT_DIR}" > /dev/null

  step "Running deployment"
  export DEPLOY_REMOTE="${REMOTE_REPO_DIR}"/.git
  export DEPLOY_ROOT="${CURRENT_PROJECT_DIR}"
  export DEPLOY_SRC="${SRC_DIR}"
  source scripts/deploy.sh >&3

  step "Checkout currently pushed branch on remote"
  git --git-dir="${DEPLOY_REMOTE}" --work-tree="${REMOTE_REPO_DIR}" branch | sed 's/\*\s//g' | xargs git --git-dir="${DEPLOY_REMOTE}" --work-tree="${REMOTE_REPO_DIR}" checkout
  git --git-dir="${DEPLOY_REMOTE}" --work-tree="${REMOTE_REPO_DIR}" branch >&3

  step "Assert remote deployment files"
  assert_deployment_files_present "${REMOTE_REPO_DIR}"

  # Assert Acquia hooks are present.
  assert_files_present_integration_acquia "${REMOTE_REPO_DIR}" "star_wars" 0

  popd > /dev/null
}