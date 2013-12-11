mkdir /var/log/openshift/logstash
cd /root
curl -O https://download.elasticsearch.org/logstash/logstash/logstash-1.2.2-flatjar.jar
cd logstash
java -jar ../logstash-1.2.2-flatjar.jar agent -f conf.d --pluginpath plugins -v
