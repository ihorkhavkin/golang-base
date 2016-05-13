FROM golang:1.5

MAINTAINER support@thumbtack.com

# Add s6 with wrappers helping to supervise processes in Docker
ADD https://github.com/just-containers/s6-overlay/releases/download/v1.11.0.1/s6-overlay-amd64.tar.gz /tmp/
RUN tar xzf /tmp/s6-overlay-amd64.tar.gz -C /

ENV LOGSTASH_MAJOR 1.5
ENV LOGSTASH_VERSION 1:1.5.6-1

RUN echo "deb http://packages.elasticsearch.org/logstash/${LOGSTASH_MAJOR}/debian stable main" \
	> /etc/apt/sources.list.d/logstash.list

# https://www.elastic.co/guide/en/logstash/2.0/package-repositories.html
# https://packages.elasticsearch.org/GPG-KEY-elasticsearch
RUN apt-key adv --keyserver ha.pool.sks-keyservers.net --recv-keys 46095ACC8548582C1A2699A9D27D666CD88E42B4

RUN apt-get update && apt-get install -y --no-install-recommends \
	awscli \
	cron \
	logstash=$LOGSTASH_VERSION \
	logrotate \
	openjdk-7-jdk \
	ruby \
	&& rm -rf /var/lib/apt/lists/*

RUN mkdir -p /image
COPY . /image
WORKDIR /image

ENV JAVA_HOME /usr/lib/jvm/java-7-openjdk-amd64

COPY lib/logstash/logstash-output-kinesis-1.6.0-java-20151207-1515-a5f95370.gem \
	/tmp/logstash-output-kinesis-1.6.0.gem
RUN /opt/logstash/bin/plugin install \
	/tmp/logstash-output-kinesis-1.6.0.gem

COPY lib/logstash/logstash-output-s3-1.0.2.9-20160511-1917-868b03a9.gem \
	/tmp/logstash-output-s3-1.0.2.9.gem
RUN /opt/logstash/bin/plugin install \
	/tmp/logstash-output-s3-1.0.2.9.gem

RUN mkdir -p /etc/logrotate.d
COPY lib/logstash/logstash_events /etc/logrotate.d/
RUN mv /etc/cron.daily/logrotate /etc/cron.hourly/logrotate

# Make directory for logrus logs
RUN mkdir -p /var/log/thumbtack/logrus

# Set up logstash environment variables
ENV LS_HOME /var/lib/logstash
ENV LS_HEAP_SIZE 500m
ENV LS_PROCESS_MEMORY 4194304
ENV LS_CONF_FILE /etc/logstash/conf.d/logstash.conf
ENV LS_LOG_DIR /var/log/logstash
ENV LS_LOG_FILE /var/log/logstash/logstash.log
ENV LS_JAVA_OPTS -Djava.io.tmpdir=/var/lib/logstash
ENV LS_NICE 19
ENV LS_HANDLES 300
ENV LS_OPTS ""

# make needs to be invoked by the service Dockerfile
# RUN make <<TARGET>>

# Generate service scripts for s6 supervisor
# Main process for Go service
RUN mkdir -p /etc/services.d/main

# NOTE: s6 will expect executable /etc/services.d/main/run script based on #!/usr/bin/with-contenv bash

# Ensure that failure of main process brings down container
COPY lib/logstash/finish /etc/services.d/main/finish

# Logstash agent
RUN mkdir -p /etc/services.d/logstash
RUN mkdir -p /var/log/thumbtack/logstash_events
COPY lib/logstash/run /etc/services.d/logstash/run

# Redirect Logstash messages via s6-log if they escape to stdin/stderr
RUN mkdir -p /etc/services.d/logstash/log
RUN mkdir -p /var/log/logstash
RUN chmod go+rw /var/log/logstash
COPY lib/logstash/log_run /etc/services.d/logstash/log/run

# Cron
RUN mkdir -p /etc/services.d/cron
COPY lib/logstash/cron_run /etc/services.d/cron/run

# s6 wrapper will use /etc/services.d/* to setup foreground processes
ENTRYPOINT ["/init"]

# Expose should be done by the service script
# EXPOSE <<PORT>>
