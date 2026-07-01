nano terraform/docker/DockerfileFROM drupal:10-apache

RUN apt-get update && apt-get install -y \
    git \
    rsync \
    && rm -rf /var/lib/apt/lists/*

#COPY drupal-settings.php /var/www/html/sites/default/settings.php

EXPOSE 80
