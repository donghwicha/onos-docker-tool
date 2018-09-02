#!/bin/bash
# -----------------------------------------------------------------------------
# ONOS container provisioning shell script.
# -----------------------------------------------------------------------------

function _usage () {
cat << _EOF_
usage: $(basename "$0")

VERSION:
  ONOS version

ONOS container provisioning shell script.

The shell script will refer to environment variables defined in bash_profile to
provision ONOS containers.

_EOF_
}

REPO_PATH="opensona"
ONOS_REPO_NAME="onos-sona-nightly-docker"
ATOMIX_REPO_NAME="atomix-docker"
ONOS_REPO_TAG="latest"
ATOMIX_REPO_TAG="latest"

[ "$1" = "-h" ] || [ "$1" = '-?' ] && _usage && exit 0

if [ -z ${1} ]; then
  ONOS_REPO_TAG="latest"
elif [ "$1" = "-s" ]; then
  ONOS_REPO_TAG="stable"
elif [ "$1" = "-d" ]; then
  ONOS_REPO_TAG="dev"
else
  ONOS_REPO_TAG="$1"
fi

echo $ONOS_REPO_TAG

# shellcheck disable=SC1091
source envSetup

if [ ${#PUBLIC_OC_IPS[@]} -eq 0 ]; then
    echo "No ONOS Controller IP addresses were configured!"
    echo "Please configure IP address in bash_profile."
    exit 1
fi

echo "Following IP addresses will be used to spawn ONOS containers."
for ((i=0; i < ${#PUBLIC_OC_IPS[@]}; i++))
{
    pub_oc_name=${PUBLIC_OC_IPS[$i]}
    echo "$pub_oc_name = ${!pub_oc_name}"
}

if [ ${#PRIVATE_OC_IPS[@]} -eq 0 ]
then
    OC_IPS=(${PUBLIC_OC_IPS[@]})
else
    OC_IPS=(${PRIVATE_OC_IPS[@]})
fi

echo "Following IP address will be used to form an ONOS cluster."
for ((i=0; i < ${#OC_IPS[@]}; i++))
{
    oc_name=${OC_IPS[$i]}
    echo "$oc_name = ${!oc_name}"
}

if [ ${#PUBLIC_OCC_IPS[@]} -eq 0 ]
then
    PUBLIC_OCC_IPS=(${PUBLIC_OC_IPS[@]})
fi

echo "Following IP address will be used to spawn storage containers."
for ((i=0; i < ${#PUBLIC_OCC_IPS[@]}; i++))
{
    pub_occ_name=${PUBLIC_OCC_IPS[$i]}
    echo "$pub_occ_name = ${!pub_occ_name}"
}

if [ ${#PRIVATE_OCC_IPS[@]} -ne 0 ]
then
    OCC_IPS=(${PRIVATE_OCC_IPS[@]})
else
    if [ ${#PUBLIC_OCC_IPS[@]} -ne 0 ]
    then
        OCC_IPS=(${PUBLIC_OCC_IPS[@]})
    else
        OCC_IPS=(${OC_IPS[@]})
    fi
fi

echo "Following IP address will be used to form storage cluster."
for ((i=0; i < ${#OCC_IPS[@]}; i++))
{
    occ_name=${OCC_IPS[$i]}
    echo "$occ_name = ${!occ_name}"
}

# start pull ONOS-SONA docker image, stop & remove ONOS-SONA container
echo "Pulling ONOS-SONA docker image..."
for ((i=0; i < ${#PUBLIC_OC_IPS[@]}; i++))
{
    pub_oc_name=${PUBLIC_OC_IPS[$i]}

    echo "Pulling ONOS-SONA docker image at ${!pub_oc_name}..."
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_oc_name}" "sudo docker pull $REPO_PATH/$ONOS_REPO_NAME:$ONOS_REPO_TAG"

    # shellcheck disable=SC2086
    if [ "$(ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@${!pub_oc_name} 'sudo docker ps -q -a -f name=onos')" ]; then
        echo "Wiping out existing ONOS-SONA container at ${!pub_oc_name}..."
        ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_oc_name}" "sudo docker stop onos || true" > /dev/null
        ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_oc_name}" "sudo docker rm onos || true" > /dev/null
    fi
}

echo "Pulling ATOMIX docker image..."
for ((i=0; i < ${#PUBLIC_OCC_IPS[@]}; i++))
{
    pub_occ_name=${PUBLIC_OCC_IPS[$i]}

    echo "Pulling ATOMIX docker image at ${!pub_occ_name}..."
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_occ_name}" "sudo docker pull $REPO_PATH/$ATOMIX_REPO_NAME:$ATOMIX_REPO_TAG"

    # shellcheck disable=SC2086
    if [ "$(ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@${!pub_occ_name} 'sudo docker ps -q -a -f name=atomix')" ]; then
        echo "Wiping out existing ATOMIX container at ${!pub_occ_name}..."
        ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_occ_name}" "sudo docker stop atomix || true" > /dev/null
        ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_occ_name}" "sudo docker rm atomix || true" > /dev/null
    fi
}

oc_ips=""
for ((i=0; i < ${#OC_IPS[@]}; i++))
{
    oc_name=${OC_IPS[$i]}
    if [ $i -eq 0 ]
    then
        oc_ips="${!oc_name}"
    else
        oc_ips="$oc_ips ${!oc_name}"
    fi
}

occ_ips=""
for ((i=0; i < ${#OCC_IPS[@]}; i++))
{
    occ_name=${OCC_IPS[$i]}
    if [ $i -eq 0 ]
    then
        occ_ips="${!occ_name}"
    else
        occ_ips="$occ_ips ${!occ_name}"
    fi
}

echo "Copying Atomix storage configs..."
for ((i=0; i < ${#PUBLIC_OCC_IPS[@]}; i++))
{
    pub_occ_name=${PUBLIC_OCC_IPS[$i]}
    occ_name=${OCC_IPS[$i]}

    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_occ_name}" "rm -rf ~/atomix_config"
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_occ_name}" "mkdir -p ~/atomix_config"

    # generate and inject atomix.json file
    echo "Generating atomix.json..."
    ATOMIX_CDEF_FILE=/tmp/"${!pub_occ_name}".atomix.json
    rm -rf $ATOMIX_CDEF_FILE
    python asset/atomix-gen-config ${!occ_name} $ATOMIX_CDEF_FILE $occ_ips
    scp -q $ATOMIX_CDEF_FILE sdn@"${!pub_occ_name}":~/atomix_config/atomix.json
}

echo "Copying ONOS cluster configs..."
for ((i=0; i < ${#PUBLIC_OC_IPS[@]}; i++))
{
    pub_oc_name=${PUBLIC_OC_IPS[$i]}
    oc_name=${OC_IPS[$i]}

    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_oc_name}" "rm -rf ~/onos_config"
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_oc_name}" "mkdir -p ~/onos_config"

    # generate and inject cluster.json file
    echo "Generating cluster.json..."
    ONOS_CDEF_FILE=/tmp/"${!pub_oc_name}".cluster.json
    rm -rf $ONOS_CDEF_FILE
    python asset/onos-gen-config ${!oc_name} $ONOS_CDEF_FILE --nodes $oc_ips
    scp -o StrictHostKeyChecking=no -o LogLevel=quiet $ONOS_CDEF_FILE sdn@"${!pub_oc_name}":~/onos_config/cluster.json

    # copy component-config file if it exists
    if [ -f $ONOS_DOCKER_SITE_ROOT/$ONOS_DOCKER_SITE/component-cfg.json ]
    then
      scp -o StrictHostKeyChecking=no -o LogLevel=quiet $ONOS_DOCKER_SITE_ROOT/$ONOS_DOCKER_SITE/component-cfg.json sdn@"${!pub_oc_name}":~/onos_config
    fi
}

echo "Launching Atomix cluster..."
for ((i=0; i < ${#PUBLIC_OCC_IPS[@]}; i++))
{
    pub_occ_name=${PUBLIC_OCC_IPS[$i]}
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_occ_name}" "sudo docker run -itd --network host --name atomix -v ~/atomix_config:/root/atomix/config $REPO_PATH/$ATOMIX_REPO_NAME:$ATOMIX_REPO_TAG"
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_occ_name}" "sudo docker ps"
}

# start ONOS-SONA container
echo "Launching ONOS cluster..."
for ((i=0; i < ${#PUBLIC_OC_IPS[@]}; i++))
{
    pub_oc_name=${PUBLIC_OC_IPS[$i]}
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_oc_name}" "sudo docker run -itd --network host --name onos -v ~/onos_config:/root/onos/config $REPO_PATH/$ONOS_REPO_NAME:$ONOS_REPO_TAG"
    ssh -o StrictHostKeyChecking=no -o LogLevel=quiet sdn@"${!pub_oc_name}" "sudo docker ps"
}

echo "Done!"
