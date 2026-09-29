extends RefCounted
class_name XbdApiClient
## XbdApiClient（小板凳API客户端）
## 只连接“小板凳”业务服务端，不允许直接访问外部AI或支付平台密钥接口。

var base_url: String = "http://127.0.0.1:8080"


func _init(url: String = "http://127.0.0.1:8080") -> void:
	base_url = url


func health_url() -> String:
	return base_url + "/health"


func catalog_url() -> String:
	return base_url + "/api/v1/catalog"


func websocket_url() -> String:
	if base_url.begins_with("https://"):
		return "wss://" + base_url.trim_prefix("https://") + "/ws"
	return "ws://" + base_url.trim_prefix("http://") + "/ws"