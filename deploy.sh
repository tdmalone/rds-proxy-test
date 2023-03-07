#!/bin/bash

set -euo pipefail

name_prefix="rds-proxy-test"
debug_mode="true"  # WARNING: Debug mode will DELETE stacks.

if [[ "${debug_mode}" == "true" ]]; then
  shellcheck --enable all "${0}"  # Self lint before running.
  cfn-lint ./*.yaml
fi


wait_while(){
  stack_name="${name_prefix}-${1}"
  waiting_stack_status="${2}"
  step_length="${3:-10}"  # in seconds.

  while true; do
    current_stack_status="$(aws cloudformation describe-stacks --stack-name "${stack_name}" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true)"
    if [[ "${current_stack_status}" == "${waiting_stack_status}" ]]; then
      echo "Waiting for ${stack_name} to finish ${waiting_stack_status}..."
      sleep "${step_length}"
    else
      echo "${stack_name} is ${current_stack_status:-deleted}."  # TODO: Error if status is ROLLBACK_IN_PROGRESS or ROLLBACK_COMPLETE (or other related status).
      break
    fi
  done
}


delete_stack(){
  stack_name="${name_prefix}-${1}"

  echo "Deleting stack ${stack_name}..."
  aws cloudformation delete-stack --stack-name "${stack_name}"
}


deploy_stack(){
  stack_name="${name_prefix}-${1}"
  stack_filename="${1}.yaml"

  echo
  echo "Creating stack ${stack_name}..."

  # Directly delete flow logs log group first, as something seems to be auto-recreating it after deletion.
  if [[ "${1}" == "1-vpc" ]]; then
    aws logs delete-log-group --log-group-name "${name_prefix}-vpc-flow-logs" 2>/dev/null || true
  fi

  aws cloudformation create-stack \
    --stack-name "${stack_name}" \
    --template-body "file://${stack_filename}" \
    --parameters ParameterKey=NamePrefix,ParameterValue="${name_prefix}" \
    --capabilities "CAPABILITY_IAM" "CAPABILITY_AUTO_EXPAND"
}


main(){

  if [[ "${debug_mode}" == "true" ]]; then
    delete_stack "4-rds-proxy"
    delete_stack "2-rds-jumpbox"

    wait_while "4-rds-proxy" "DELETE_IN_PROGRESS"
    delete_stack "3-rds"

    wait_while "3-rds" "DELETE_IN_PROGRESS"
    wait_while "2-rds-jumpbox" "DELETE_IN_PROGRESS"
    delete_stack "1-vpc"

    wait_while "1-vpc" "DELETE_IN_PROGRESS"
  fi

  deploy_stack "1-vpc"

  wait_while "1-vpc" "CREATE_IN_PROGRESS"
  deploy_stack "2-rds-jumpbox"
  deploy_stack "3-rds"

  wait_while "3-rds" "CREATE_IN_PROGRESS"
  deploy_stack "4-rds-proxy"

  wait_while "2-rds-jumpbox" "CREATE_IN_PROGRESS"
  wait_while "4-rds-proxy" "CREATE_IN_PROGRESS"
  echo
  echo "Done."
}


main
