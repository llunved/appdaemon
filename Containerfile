ARG OS_RELEASE=33
ARG OS_IMAGE=fedora:$OS_RELEASE

FROM $OS_IMAGE as build

ARG OS_RELEASE
ARG OS_IMAGE
ARG HTTP_PROXY=""
ARG USER="appdaemon"
ARG DEVBUILD=""

LABEL MAINTAINER riek@llunved.net

ENV LANG=C.UTF-8
ENV VOLUMES="/etc/appdaemon /var/lib/appdaemon /var/log/appdaemon /usr/share/doc/appdaemon/config /etc/localtime"

USER root

RUN mkdir -p /appdaemon
WORKDIR /appdaemon

ADD ./rpmreqs-build.txt /appdaemon/

ENV http_proxy=$HTTP_PROXY
RUN dnf -y install https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$OS_RELEASE.noarch.rpm \
    https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$OS_RELEASE.noarch.rpm \
    && dnf -y upgrade \
    && dnf -y install $(cat rpmreqs-build.txt) 

ADD ./rpmreqs-rt.txt ./rpmreqs-dev.txt /appdaemon/
# Create the minimal target environment
RUN mkdir /sysimg \
    && dnf install --installroot /sysimg --releasever $OS_RELEASE --setopt install_weak_deps=false --nodocs -y coreutils-single glibc-minimal-langpack $(cat rpmreqs-rt.txt) \
    && if [ "${DEVBUILD}" == "True"]; then dnf install --installroot /sysimg --releasever $OS_RELEASE --setopt install_weak_deps=false --nodocs -y $(cat rpmreqs-dev.txt); fi \
    && rm -rf /sysimg/var/cache/*

RUN cp /sysimg/usr/share/zoneinfo/America/New_York /sysimg/etc/localtime

#Add the insteon user both in the build and rt contexts
RUN adduser -u 1010 -r -g root -G dialout -d /appdaemon -s /sbin/nologin -c "appdaemon user" $USER
RUN adduser -R /sysimg -u 1010 -r -g root -G dialout -d /appdaemon -s /sbin/nologin -c "appdaemon user" $USER

RUN chown -R $USER:0 /appdaemon
USER $USER


ADD . /appdaemon/

#RUN /usr/bin/python3 -m virtualenv -v /appdaemon/ 
RUN virtualenv -p /usr/bin/python3 --copies -v /appdaemon/ 

RUN source /appdaemon/bin/activate && /appdaemon/bin/pip3 install /appdaemon/
RUN rm -rf /appdaemon/.cache

# Workarond for https://stackoverflow.com/questions/12020885/python-converting-file-to-base64-encoding
RUN sed -i 's/base64.decodestring/base64.decodebytes/g' lib/python3.9/site-packages/feedparser.py

USER root
RUN cp -pR /appdaemon/ /sysimg/appdaemon/
 
# Move the appdaemon config, so we can mount it persistently from the host
#RUN if [ -d /sysimg/etc/appdaemon ]; then mv -fv /sysimg/etc/appdaemon /sysimg/etc/appdaemon.default ; fi
#RUN if [ -d /sysimg/var/www ]; then mv -fv /sysimg/var/www /sysimg/var/www.default ; fi
RUN mkdir -p /sysimg/usr/share/doc/appdaemon.default/config/etc && \
    mv -fv /sysimg/appdaemon/conf /sysimg/usr/share/doc/appdaemon.default/config/etc/appdaemon

FROM scratch AS runtime

COPY --from=build /sysimg /

WORKDIR /var/lib/appdaemon

ENV VOLUMES="/etc/appdaemon /var/lib/appdaemon /var/log/appdaemon /usr/share/doc/appdaemon/config /etc/localtime"
ENV USER=$USER
ENV CHOWN=true 
ENV CHOWN_DIRS="/etc/appdaemon /var/lib/appdaemon /var/log/appdaemon" 
 
VOLUME VOLUMES

ADD ./install.sh \ 
    ./upgrade.sh \
    ./uninstall.sh \
    ./entrypoint.sh \
    ./init_container.sh /sbin
ADD ./start.sh /bin
 
RUN chmod +x /sbin/install.sh \
             /sbin/upgrade.sh \
             /sbin/uninstall.sh \
             /sbin/entrypoint.sh \
             /sbin/init_container.sh \
             /bin/start.sh
  
EXPOSE 5050
ENTRYPOINT ["/sbin/entrypoint.sh"]
CMD ["/bin/start.sh"]

# MOVIGN AWAY FROM THIS PATTERN TOWARDS PODS
#LABEL RUN="podman run --rm -t -i --name ${NAME} --net=host -v /var/lib/${NAME}/www:/var/www:rw,z -v etc/${NAME}:/etc/${NAME}:rw,z -v /var/log/${NAME}:/var/log/${NAME}:rw,z ${IMAGE}"
#LABEL INSTALL="podman run --rm -t -i --privileged --rm --net=host --ipc=host --pid=host -v /:/host -v /run:/run -e HOST=/host -e IMAGE=\$IMAGE -e NAME=\$NAME -e CONFDIR=/etc -e LOGDIR=/var/log -e DATADIR=/var/lib --entrypoint /bin/sh  \$IMAGE /sbin/install.sh"
#LABEL UPGRADE="podman run --rm -t -i --privileged --rm --net=host --ipc=host --pid=host -v /:/host -v /run:/run -e HOST=/host -e IMAGE=\$IMAGE -e NAME=\$NAME -e CONFDIR=/etc -e LOGDIR=/var/log -e DATADIR=/var/lib --entrypoint /bin/sh  \$IMAGE /sbin/upgrade.sh"
#LABEL UNINSTALL="podman run --rm -t -i --privileged --rm --net=host --ipc=host --pid=host -v /:/host -v /run:/run -e HOST=/host -e IMAGE=\$IMAGE -e NAME=\$NAME -e CONFDIR=/etc -e LOGDIR=/var/log -e DATADIR=/var/lib --entrypoint /bin/sh  \$IMAGE /sbin/uninstall.sh"

