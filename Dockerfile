FROM ubuntu/apache2:2.4-20.04_beta
RUN apt-get update \
    && apt-get install -y iputils-ping \
    && apt-get install -y net-tools\
    && apt-get install jq -y
# Ping utils allow containers to test communication between containers in default and custom networks.

#copy files into html directory 
COPY my-app /var/www/html
ARG PORT=80
EXPOSE $PORT

ENTRYPOINT ["apachectl", "-D", "FOREGROUND"]

