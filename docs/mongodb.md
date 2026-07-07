Client → HAProxy (single IP/DNS) → NodePort on cluster nodes → MongoDB Service/Pod


kubectl exec -it -n team1 mongodb-0 -- mongosh --port 28017 -u $user -p $PW --authenticationDatabase team1_mongo

kubectl exec -it -n team1 mongodb-0 -- mongosh --port 28017 --tls --tlsAllowInvalidCertificates --tlsAllowInvalidHostnames -u $user -p $PW --authenticationDatabase team1_mongo

kubectl exec -it -n team1 mongodb-0 -- mongosh --port 28017 -u $user -p $PW --authenticationDatabase admin
