#!/bin/bash

# Script to setup and boot cloud image VMs in kvm
# v.0.7.20

## Usage
#"-h|--help" help info
#"-n|--name" vm name
#"-c|--cores" number of cores
#"-m|--memory" memory in MB
#"-s|--sshkey" path to public ssh key
#"-i|--image" path to cloud image to use (ubuntu or centos)
#"-d|--delete" delete VM

# Directory of the script
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
SCRIPT_NAME="$(echo $0 | sed 's|\.\/||g')"

# Directory to store images
DIR=/virt/images
mkdir -p $DIR

# Location of cloud image
CENTOS_IMAGE=$DIR/CentOS-7-x86_64-GenericCloud.qcow2
#UBUNTU_IMAGE=$DIR/bionic-server-cloudimg-amd64.img
UBUNTU_IMAGE=$DIR/xenial-server-cloudimg-amd64-disk1.img

# read the options
TEMP=$(getopt -o n:c:m:s:i:dh --long name:,cores:,memory:,sshkey:,image:,delete,help -n 'build-vm.sh' -- "$@")
eval set -- "$TEMP"

# set an initial value for the flags
HELP=0
VM_NAME=""
CORES="1"
MEMORY="512"
SSH_KEY_FILE=/root/.ssh/id_rsa.pub
IMAGE="$UBUNTU_IMAGE"
DELETE="0"

while true ;
do
    case "$1" in
        -h|--help) HELP=1; shift;;
        -n|--name) case "$2" in
            "") shift 2;;
            *) VM_NAME=$2; shift 2;;
            esac;;
        -c|--cores) case "$2" in
            "") shift 2;;
            *) CORES=$2; shift 2;;
            esac;;
        -m|--memory) case "$2" in
            "") shift 2;;
            *) MEMORY="$2"; shift 2;;
            esac;;
        -s|--sshkey) case "$2" in
            "") shift 2;;
            *) SSH_KEY_FILE="$2"; shift 2;;
            esac;;
        -i|--image) case "$2" in
            "") shift 2;;
            *) IMAGE="$2"; shift 2;;
            esac;;
        -d|--delete) DELETE=1; shift;;
        --) shift ; break ;;
        *) echo -e "Error: invalid argument\n" ; exit 3 ;;
    esac
done

#if -h | --help option is selected show usage
if [ $HELP -eq 1 ]
then
	echo -e "build-vm.sh, usage: bash $SCRIPT_NAME -n|--name <VM_NAME> [-c|--cores <CORES_#>] [-m|--memory <MEMORY_IN_MB>] [-s|--sshkey <PUBLIC_SSH_KEY_FILE>] [-i|--image <IMAGE_FILE>] [-d|--delete]\n"
	echo -e '"-h|--help" help info
"-n|--name" vm name
"-c|--cores" number of cores
"-m|--memory" memory in MB
"-s|--sshkey" path to public ssh key
"-i|--image" path to cloud image to use (ubuntu or centos)
"-d|--delete" delete VM\n'
	exit 0
fi

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
   echo -e "\nERROR: This script must be run as root\n" 1>&2
   exit 1
fi
##

# Validate VM_NAME was provided
if [ -z $VM_NAME ]; then
	echo -e "Error: VM name must be provided. \n"
	echo -e "build-vm.sh, usage: bash $SCRIPT_NAME -n|--name <VM_NAME> [-c|--cores <CORES_#>] [-m|--memory <MEMORY_IN_MB>] [-s|--sshkey <PUBLIC_SSH_KEY_FILE>] [-i|--image <IMAGE_FILE>] [-d|--delete]\n"
	exit 4
fi

# Validate VM deletion
if [ $DELETE -eq 1 ]
then
  ls -ld $DIR/$VM_NAME > /dev/null 2>&1
  VM_STATUS=$?
  if [ $VM_STATUS -ne '0' ]; then
	  echo -e "Error: $VM_NAME VM not found. \n"
	  exit 5
  else
    virsh destroy $VM_NAME
    virsh undefine $VM_NAME
    rm -rf $DIR/$VM_NAME > /dev/null 2>&1
    sed -i "/ ${VM_NAME}$/d" /etc/hosts > /dev/null 2>&1
    echo -e "$VM_NAME has been deleted \n"
    exit 0
  fi
fi

# Validate ssh public key
ssh-keygen -l -f "$SSH_KEY_FILE" > /dev/null 2>&1
KEY_STATUS=$?
if [ $KEY_STATUS -ne '0' ]; then
	echo -e "Error: $SSH_KEY_FILE is not a public key file. \n"
	echo -e "build-vm.sh, usage: bash $SCRIPT_NAME -n|--name <VM_NAME> [-c|--cores <CORES_#>] [-m|--memory <MEMORY_IN_MB>] [-s|--sshkey <PUBLIC_SSH_KEY_FILE>] [-i|--image <IMAGE_FILE>] [-d|--delete]\n"
	exit 6
fi

# Validate image file
qemu-img check "$IMAGE" > /dev/null 2>&1 
IMAGE_STATUS=$?
if [ $IMAGE_STATUS -ne '0' ]; then
	echo -e "Error: $IMAGE is not a valid qcow2 file. \n"
	echo -e "build-vm.sh, usage: bash $SCRIPT_NAME -n|--name <VM_NAME> [-c|--cores <CORES_#>] [-m|--memory <MEMORY_IN_MB>] [-s|--sshkey <PUBLIC_SSH_KEY_FILE>] [-i|--image <IMAGE_FILE>] [-d|--delete]\n"
	exit 7
fi

## Variables

# Cloud init files
USER_DATA=user-data
META_DATA=meta-data
CI_ISO=$VM_NAME-cidata.iso
DISK=$VM_NAME.qcow2

# Bridge for VMs
BRIDGE=virbr0

#-----------------------------------------------------------

# Ready for build process
echo -e "\nBuilding VM $VM_NAME with $CORES cores and $MEMORY MB of ram using image $IMAGE...\n"

# Check if domain already exists
virsh dominfo $VM_NAME > /dev/null 2>&1
if [ "$?" -eq 0 ]; then
    echo -n "[WARNING] $VM_NAME already exists.  "
    read -p "Do you want to overwrite $VM_NAME [y/N]? " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo ""
    else
        echo -e "\nNot overwriting $VM_NAME. Exiting..."
        exit 1
    fi
fi

# User of cloud image
if [ $IMAGE = $CENTOS_IMAGE ]; then
  USER_IMG=centos;
  RM_CLOUDINIT=$(echo "yum, -y, remove, cloud-init")
  OS_VARIANT="centos7.0"
elif [ $IMAGE == $UBUNTU_IMAGE ]; then
  USER_IMG=ubuntu;
  RM_CLOUDINIT=$(echo "apt-get, remove, cloud-init, -y")
  OS_VARIANT="ubuntu16.04"
else
  USER_IMG=cloud-user;
  OS_VARIANT="auto"
fi

# Start clean
rm -rf $DIR/$VM_NAME
mkdir -p $DIR/$VM_NAME
SSH_KEY=$(cat $SSH_KEY_FILE)

pushd $DIR/$VM_NAME > /dev/null

    # Create log file
    touch $VM_NAME.log

    echo "$(date -R) Destroying the $VM_NAME domain (if it exists)..."

    # Remove domain with the same name
    virsh destroy $VM_NAME >> $VM_NAME.log 2>&1
    virsh undefine $VM_NAME >> $VM_NAME.log 2>&1

    # cloud-init config: set hostname, remove cloud-init package,
    # and add ssh-key
    cat > $USER_DATA << _EOF_

#cloud-config

# Hostname management
preserve_hostname: False
hostname: $VM_NAME
fqdn: $VM_NAME.example.com

# Set root pass
users:
  - name: root
  - name: $USER_IMG
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    shell: /bin/bash
    ssh-authorized-keys:
      - $SSH_KEY
chpasswd:
  list: |
    root:${USER_IMG}
    $USER_IMG:t3mp0r4l
  expire: False

# Intall some extra packages
# packages:
#   - epel-release
#   - telnet
#   - nmap
#   - bind-utils
#   - bash-completion

# Upgrade system
#package_upgrade: true

# Remove cloud-init when finished with it
runcmd:
  - [ $RM_CLOUDINIT ]

# Configure where output will go
output:
  all: ">> /var/log/cloud-init.log"

_EOF_

    echo "instance-id: $VM_NAME; local-hostname: $VM_NAME" > $META_DATA

    echo "$(date -R) Copying template image..."
    cp $IMAGE $DISK

    # Create CD-ROM ISO with cloud-init config
    echo "$(date -R) Generating ISO for cloud-init..."
    genisoimage -output $CI_ISO -volid cidata -joliet -r $USER_DATA $META_DATA &>> $VM_NAME.log

    echo -e "$(date -R) Installing the domain and adjusting the configuration...\n"
    echo "[INFO] Installing with the following parameters:"
    echo "VM name=$VM_NAME ram=$MEMORY vcpus=$CORES bridge=$BRIDGE"

    virt-install --import --name $VM_NAME --ram $MEMORY --vcpus $CORES --disk \
    $DISK,format=qcow2,bus=virtio --disk $CI_ISO,device=cdrom --network \
    bridge=$BRIDGE,model=virtio --os-type=linux --os-variant=$OS_VARIANT --noautoconsole

    MAC=$(virsh dumpxml $VM_NAME | awk -F\' '/mac address/ {print $2}')
    while true
    do
        IP=$(grep -B1 $MAC /var/lib/libvirt/dnsmasq/$BRIDGE.status | head \
             -n 1 | awk '{print $2}' | sed -e s/\"//g -e s/,//)
        if [ "$IP" = "" ]
        then
            sleep 1
        else
            break
        fi
    done

    # Eject cdrom
    echo -e "\n$(date -R) Cleaning up cloud-init..."
    virsh change-media $VM_NAME hda --eject --config >> $VM_NAME.log

    # Remove the unnecessary cloud init files
    rm $USER_DATA $CI_ISO

    # Update /etc/hosts
    sed -i "/ ${VM_NAME}$/d" /etc/hosts > /dev/null 2>&1
    echo "$IP ${VM_NAME}.example.com $VM_NAME" >> /etc/hosts

    echo -e "$(date -R) DONE.\n"
    echo -e "SSH to $VM_NAME using ' ssh ${USER_IMG}@${VM_NAME} ' with the corresponding private key for $SSH_KEY_FILE\n"

popd > /dev/null

exit 0
