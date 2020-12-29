#!/bin/bash


set -x

SERVICE=$IMAGE

env

# Make sure the host is mounted
if [ ! -d /host/etc -o ! -d /host/proc -o ! -d /host/var/run ]; then
	    echo "Host file system is not mounted at /host" >&2
	        exit 1
fi


chroot /host sh -c "/usr/bin/systemctl stop ${NAME} && sleep 30 && /usr/bin/podman rm ${NAME} && sleep 15"

chroot /host /usr/bin/podman create --name ${NAME} -p 5050 --net=host -v ${CONFDIR}/${NAME}:/etc/${NAME}:rw,z -v ${LOGDIR}/${NAME}:/var/log/${NAME}:rw,z --entrypoint /sbin/entrypoint.sh ${IMAGE} /bin/start.sh

chroot /host sh -c "/usr/bin/podman generate systemd --restart-policy=always -t 1 ${NAME} > /etc/systemd/system/${NAME}.service && systemctl daemon-reload"
chroot /host sh -c "/usr/bin/systemctl start ${NAME} "

