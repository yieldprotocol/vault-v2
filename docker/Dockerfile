FROM node:10.21.0-buster

RUN mkdir -p /srv/ytoken-mvp
COPY docker/entrypoint.sh /srv/ytoken-mvp/entrypoint.sh
RUN chmod +x /srv/ytoken-mvp/entrypoint.sh
COPY .  /srv/ytoken-mvp

WORKDIR /srv/ytoken-mvp

RUN npm cache verify  && yarn

ENTRYPOINT [ "/srv/ytoken-mvp/entrypoint.sh" ]