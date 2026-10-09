FROM grafana/grafana:11.2.0

USER root

COPY grafana-entrypoint.sh /grafana-entrypoint.sh
COPY provisioning/ /etc/grafana/provisioning/
COPY dashboards/ /var/lib/grafana/dashboards/

RUN chmod 0755 /grafana-entrypoint.sh \
 && chown -R 472:0 /etc/grafana/provisioning /var/lib/grafana/dashboards

USER 472

ENTRYPOINT ["/grafana-entrypoint.sh"]
