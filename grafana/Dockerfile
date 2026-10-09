FROM grafana/grafana:11.6.11

USER root

ENV GF_PATHS_PLUGINS=/usr/share/grafana/plugins-external

RUN apk add --no-cache su-exec \
 && mkdir -p "${GF_PATHS_PLUGINS}" \
 && grafana cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install yesoreyeram-infinity-datasource 4.1.1 \
 && grafana cli --pluginsDir "${GF_PATHS_PLUGINS}" plugins install grafana-clock-panel 3.2.4 \
 && chown -R 472:0 "${GF_PATHS_PLUGINS}"

COPY grafana-entrypoint.sh /grafana-entrypoint.sh
COPY provisioning/ /etc/grafana/provisioning/
COPY dashboards/ /etc/grafana/dashboards/

RUN chmod 0755 /grafana-entrypoint.sh \
 && chown -R 472:0 /etc/grafana/provisioning /etc/grafana/dashboards

ENTRYPOINT ["/grafana-entrypoint.sh"]
