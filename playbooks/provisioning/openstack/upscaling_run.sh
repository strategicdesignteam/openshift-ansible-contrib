#!/bin/bash

# Parameters:
# -i INV          path to ansible inventory
# -e nodes=NUMBER number of nodes after upscaling
# -o OSH_ANSIBLE  path to openshift-ansible directory
# -c CONTRIB      path to openshift-ansible-contrib directory
# -h              displays script information, usage
# -v              sets verbosity in ansible-playbook

# Variables
ANSIBLE_PARAMS="--user openshift --private-key ~/.ssh/openshift"
INVENTORY=
OPENSHIFT_ANSIBLE="../../../../openshift-ansible"
OPENSHIFT_ANSIBLE_CONTRIB="./openshift-ansible-contrib"
NODES_VAR=
VERBOSE= # for now, it means -vvv
USAGE="Description: This script runs up-scaling method.

Usage: ./`basename $0` [-h] [-e nodes=N] -i path_to_inventory

Parameters:
-h                     Display this message.
-i path_to_inventory   Set path to inventory directory.
-e nodes=N             Set number of nodes after autoscaling.
                       If not set, deployment is incremented by 1 by default.
-o path_to_osh_ansible Set path to openshift-ansible.
-c path_to_contrib     Set path to openshift-ansible-contrib.
-v                     Set output verbosity (to -vvv)."

# Parse arguments
while [[ $# -gt 0 ]]; do
  arg="$1"
  case $arg in
    -e|--external)
      NODES_VAR="$2"
      shift;shift
      ;;
    -i|--inventory)
      INVENTORY="${2%/}"
      if [[ ! -d $INVENTORY ]]; then
        echo "$INVENTORY is not a directory." >&2
        exit 1
      fi
      shift;shift
      ;;
    -o|--openshift)
      OPENSHIFT_ANSIBLE="${2%/}"
      if [[ ! -d $OPENSHIFT_ANSIBLE ]]; then
        echo "$OPENSHIFT_ANSIBLE is not a directory." >&2
        exit 1
      fi
      shift;shift
      ;;
    -c|--contrib)
      OPENSHIFT_ANSIBLE_CONTRIB="${2%/}"
      if [[ ! -d $OPENSHIFT_ANSIBLE_CONTRIB ]]; then
        echo "$OPENSHIFT_ANSIBLE_CONTRIB is not a directory." >&2
        exit 1
      fi
      shift;shift
      ;;
    -h|--help)
      echo "$USAGE"
      exit 0
      ;;
    -v|--verbose)
      VERBOSE="-vvv"
      shift
      ;;
    *)
      echo "Unknown argument '$arg'." >&2
      exit 1
      ;;
  esac
done

# Check that -i (required) argument is not empty
if [[ -z "${INVENTORY}" ]]; then
  echo "Parameter -i is required. For more information, use -h|--help." >&2
  exit 1
fi

# If set, check that -e matches "nodes=<number>"
if [[ -n "${NODES_VAR}" ]] && [[ ! ("$NODES_VAR" =~ ^nodes=[0-9]+$) ]]; then
  echo "Argument '-e $NODES_VAR' is invalid. For more information, use -h|--help." >&2
  exit 1
fi

# Run upscaling_pre-tasks.yaml to:
# - run preverification based on entered number of nodes
# - update openstack_num_nodes variable in inventory

# If nodes was not set, let it increment by 1 by default
if [[ -z "${NODES_VAR}" ]]; then
  ansible-playbook $ANSIBLE_PARAMS -i "$INVENTORY" \
  $OPENSHIFT_ANSIBLE_CONTRIB/playbooks/provisioning/openstack/upscaling_pre-tasks.yaml \
  $VERBOSE
else
  ansible-playbook $ANSIBLE_PARAMS -i "$INVENTORY" \
  $OPENSHIFT_ANSIBLE_CONTRIB/playbooks/provisioning/openstack/upscaling_pre-tasks.yaml \
  -e "$NODES_VAR" $VERBOSE
fi

# Check that pre-tasks were successfully completed
if [[ $? -ne 0 ]]; then
  exit 1
fi

# Get nodes value from updated inventory if -e was not passed by user
if [[ -z "${NODES_VAR}" ]]; then
    N=`sed -n "s/^openstack_num_nodes: \([0-9]\+\)$/\1/p" $INVENTORY/group_vars/all.yml`

    # Verify that value was found
    if [[ -z "${N}" ]]; then
      echo "Number of nodes not defined in the inventory file." >&2
      exit 1
    else
      NODES_VAR="nodes=$N"
    fi
fi

# Run upscaling_scale-up.yaml to:
# - rerun provisioning and installation
# - verify the result
ansible-playbook $ANSIBLE_PARAMS -i "$INVENTORY" \
$OPENSHIFT_ANSIBLE_CONTRIB/playbooks/provisioning/openstack/upscaling_scale-up.yaml \
-e "$NODES_VAR" -e "openshift_ansible_dir=`realpath $OPENSHIFT_ANSIBLE`" \
-e "openshift_ansible_contrib_dir=`realpath $OPENSHIFT_ANSIBLE_CONTRIB`" $VERBOSE
