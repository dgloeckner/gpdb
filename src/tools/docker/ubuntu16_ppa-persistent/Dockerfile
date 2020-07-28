FROM ubuntu:18.04
EXPOSE 5432
# How many Greenplum segments to create.
ENV NUMSEGMENTS=10

ADD container_init.sh /container_init.sh
ADD gpdb_start.sh /gpdb_start.sh

CMD bash /container_init.sh && tail -f /dev/null

