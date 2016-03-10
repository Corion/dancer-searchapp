# My Dockerfile for Dancer-SearchApp
# DOCKER-VERSION 0.3.4
FROM        perl:latest
MAINTAINER  Max Maischein <corion@corion.net>

# For running Tika
#RUN apt-get update && apt-get install default-jre-headless
RUN apt-get update && apt-get install -y default-jre-headless

RUN curl -L http://cpanmin.us | perl - App::cpanminus
RUN cpanm Twiggy

RUN git clone git://192.168.99.1/Dancer-SearchApp

# Install Tika
RUN mkdir Dancer-SearchApp/jar && curl http://www.apache.org/dyn/closer.cgi/tika/tika-server-1.12.jar -o Dancer-SearchApp/jar/tika-server-1.12.jar

# Install App prerequisites
RUN cd Dancer-SearchApp && cpanm --installdeps .

# We should document the mountpoints
# ... and install a cron job for scanning mounted directories

EXPOSE 8080

WORKDIR Dancer-SearchApp
# ENV # the elasticsearch we will use to store the data
ENTRYPOINT ["plackup","-s","Twiggy", "-a", "bin/app.pl"]
CMD ["--port", "8080"] 