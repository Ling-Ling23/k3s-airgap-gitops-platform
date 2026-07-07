after cfg update
git pull
kaf infra/kube-system/haproxy/haproxy.yaml
kubectl rollout restart deployment haproxy -n kube-system


kubectl -n kube-system set image pod/svclb-haproxy-ad463cba-rp6kf  lb-tcp-8443=$ARTIFACTORY/rancher/klipper-lb:v0.4.13
kubectl -n kube-system set image pod/svclb-haproxy-ad463cba-rp6kf  lb-tcp-28017=$ARTIFACTORY/rancher/klipper-lb:v0.4.13
kubectl -n kube-system set image pod/svclb-haproxy-ad463cba-rp6kf lb-tcp-9443=$ARTIFACTORY/rancher/klipper-lb:v0.4.13
kubectl -n kube-system set image pod/svclb-haproxy-ad463cba-rp6kf lb-tcp-443=$ARTIFACTORY/rancher/klipper-lb:v0.4.13
kubectl -n kube-system set image pod/svclb-haproxy-ad463cba-rp6kf lb-tcp-8220=$ARTIFACTORY/rancher/klipper-lb:v0.4.13
kubectl -n kube-system set image pod/svclb-haproxy-ad463cba-rp6kf lb-tcp-3306=$ARTIFACTORY/rancher/klipper-lb:v0.4.13

