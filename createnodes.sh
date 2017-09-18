#!/bin/bash

#Maximum number of working nodes permited
HIGH_LIMIT=5
#Virtual machine template to clone
VMTEMPLATE="stratum"
#Name prefix for the nodes
PREFIX="K"
#Read the command line options
# -i <ssh key to connect to VMs>
# -n <number of nodes>
# -p <prefix to names>
while getopts :n:p: opt; do
	case $opt in 
	n)
		if [ -n "$WORK_NODES" ]; then
		       echo "repeated option -$opt" >&2
		       exit 2
	       fi
		WORK_NODES=$OPTARG
		if ! [[ $WORK_NODES =~ ^[0-9]+$ ]]; then
		    echo "-n needs a number as argument" >&2
		    exit 2
		fi
		if [ $WORK_NODES -gt $HIGH_LIMIT -o $WORK_NODES -le 0 ]; then
			echo "Number of nodes must be between 1 and $HIGH_LIMIT" >&2
			exit 2
		fi
		;;
	p)
		if [ $PREFIX != "K" ]; then
			echo "repeated option -$opt" >&2
			exit 3
		fi
		PREFIX=$OPTARG
				if ! [[ $PREFIX =~ ^[a-zA-Z]+$ ]]; then
			echo "-p needs a character's string" >&2
			exit 3
		fi
		;;
	\?)
		echo "Invalid option -$OPTARG" >&2
		;;
	:)
		echo "Option -$OPTARG requires an argument" >&2
		;;
	esac
done

if [ -n "$PREFIX" -a -n "$WORK_NODES" ]; then
	echo "Creating VMs"
	virt-clone --original $VMTEMPLATE --auto-clone --name ${PREFIX}master || exit 4
	virsh start ${PREFIX}master || exit 4
else
	echo "Usage $0 -n <number of working nodes> -p <Node name prefix>" >&2
	exit 4
fi

PROCESS_NODE=1
while [ $WORK_NODES -ge $PROCESS_NODE ]; do
    virt-clone --original $VMTEMPLATE --auto-clone --name ${PREFIX}node${PROCESS_NODE} || exit 4
    virsh start ${PREFIX}node${PROCESS_NODE} || exit 4
    ((PROCESS_NODE++))
done

#Get vIPs from VMs, I only take the first network interface
echo "Finding Node IPs"
while true; do
    KMASTER_IP=$(virsh -q domifaddr ${PREFIX}master|head -1|awk '{print $4}'|cut -d'/' -f1)
    if [ -z "$KMASTER_IP" ]; then
	    echo "Waiting for master's IP..."
	    sleep 5
    else
            echo " Master IP=$KMASTER_IP"
	    break
    fi
done
PROCESS_NODE=1
KNODE_IPS=""
while [ $WORK_NODES -ge $PROCESS_NODE ]; do
    while true; do
   	 THIS_NODE_IP="$(virsh -q domifaddr ${PREFIX}node${PROCESS_NODE}|head -1|awk '{print $4}'|cut -d'/' -f1)"
   	if [ -z "$THIS_NODE_IP" ]; then
   		echo "Waiting for Node$[PROCESS_NODE]'s IP..."
   		sleep 5
   	else
   		echo " Node${PROCESS_NODE} IP=$THIS_NODE_IP"
   		KNODE_IPS="$KNODE_IPS $THIS_NODE_IP"
   		break
   	fi
   done
    ((PROCESS_NODE++))
done
echo "Saving the IPs in the inventory file"
ALL_NODES="[${PREFIX}_cluster]\n$KMASTER_IP hostname=${PREFIX}master\n"
#echo "[${PREFIX}_cluster]" >> ./inventory
MASTER_NODE="[${PREFIX}_master]\n$KMASTER_IP hostname=${PREFIX}master\n"
#echo "$KMASTER_IP hostname=${PREFIX}master" >> ./inventory
NODE_NUMBER=1
NODE_NODES="[${PREFIX}_nodes]\n"
for NIP in $KNODE_IPS; do
	ALL_NODES="${ALL_NODES}$NIP hostname=${PREFIX}node${NODE_NUMBER}\n"
	NODE_NODES="${NODE_NODES}$NIP hostname=${PREFIX}node${NODE_NUMBER}\n"
	#echo "$NIP hostname=${PREFIX}node${NODE_NUMBER}" >> ./inventory
	((NODE_NUMBER++))
done
echo -e "${ALL_NODES}\n${MASTER_NODE}\n${NODE_NODES}\n" >> ./inventory
#echo "" >> ./inventory


