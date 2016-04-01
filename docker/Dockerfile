# My Dockerfile for Dancer-SearchApp
# DOCKER-VERSION 0.3.4
#
# Invoke from the distribution directory as
#     docker -t dancer-searchapp -f docker/Dockerfile .
#
FROM        perl:latest
MAINTAINER  Max Maischein <corion@corion.net>

# For running Tika
RUN apt-get update && apt-get install -y \
  default-jre-headless \
   && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /root/Dancer-SearchApp

# Install Tika
RUN mkdir /root/Dancer-SearchApp/jar \
&& curl http://www.apache.org/dyn/closer.cgi/tika/tika-server-1.12.jar -o Dancer-SearchApp/jar/tika-server-1.12.jar

# Install Elasticsearch
# + Language detection plugin

# Pre-cache some modules we will most likely use
RUN    cpanm --notest \
           Promises \
           Dancer \
           JSON \
           YAML \
           Twiggy \
           Template \
           Search::Elasticsearch::Async \
           Mail::IMAPClient \
           Image::ExifTool \
           MP3::Tag \
           Plack::Middleware::Pod \
           Text::Markdown \
    && rm -fr /root/.cpanm /tmp/*


# Copy the current build into the Docker image
COPY . /root/Dancer-SearchApp/

# Install App prerequisites, using --notest to speed things up vastly,
# at the cost of not testing the resulting setup
RUN    cd /root/Dancer-SearchApp \
    && cpanm --notest --installdeps . \
    && rm -fr /root/.cpanm /tmp/*

# We should document the mountpoints
# ... and install a cron job for scanning mounted directories

EXPOSE 8080

WORKDIR /root/Dancer-SearchApp
# ENV # the elasticsearch we will use to store the data
ENTRYPOINT ["/root/Dancer-SearchApp/docker/docker-entrypoint.sh"]
# use docker run -d -P -name config -v ../config-examples:/config ...
VOLUME /es-data
CMD ["--port", "8080"] 