# My Dockerfile for Dancer-SearchApp
# DOCKER-VERSION 0.3.4
FROM        perl:latest
MAINTAINER  Max Maischein <corion@corion.net>

# For running Tika
RUN apt-get update && apt-get install -y \
  default-jre-headless \
  cpanminus \
  twiggy \
   && rm -rf /var/lib/apt/lists/*

RUN mkdir -p Dancer-SearchApp

# Install Tika
RUN mkdir Dancer-SearchApp/jar \
&& curl http://www.apache.org/dyn/closer.cgi/tika/tika-server-1.12.jar -o Dancer-SearchApp/jar/tika-server-1.12.jar

# Install Elasticsearch
# + Language detection plugin

# Copy the current build into the Docker image
COPY ../ Dancer-SearchApp/

# Install App prerequisites
RUN cd Dancer-SearchApp && cpanm --installdeps .

# We should document the mountpoints
# ... and install a cron job for scanning mounted directories

EXPOSE 8080

WORKDIR Dancer-SearchApp
# ENV # the elasticsearch we will use to store the data
ENTRYPOINT ["plackup","-s","Twiggy", "-a", "bin/app.pl"]
VOLUME /config
# use docker run -d -P -name config -v ../config-examples:/config ...
VOLUME /es-data
CMD ["--port", "8080"] 