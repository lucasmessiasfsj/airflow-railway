FROM grafana/grafana:11.2.0

USER root

RUN apk add --no-cache su-exec

COPY grafana-entrypoint.sh /grafana-entrypoint.sh
COPY provisioning/ /etc/grafana/provisioning/
COPY dashboards/ /etc/grafana/dashboards/

RUN chmod 0755 /grafana-entrypoint.sh \
 && chown -R 472:0 /etc/grafana/provisioning /etc/grafana/dashboards

ENTRYPOINT ["/grafana-entrypoint.sh"]
