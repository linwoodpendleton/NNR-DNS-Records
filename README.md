# NNR-DNS-Records
NNR更新记录脚本


请用一个没有用的域名做,因为会删除所有记录.如何不需要删除的请修改以下代码

# List of records to keep
keep_records=("www.$DOMAIN" "api1.$DOMAIN" "api2.$DOMAIN" "api3.$DOMAIN" "$DOMAIN")

使用前要安装JQ库



debian ubuntu


apt install jq



centos


yum install jq
