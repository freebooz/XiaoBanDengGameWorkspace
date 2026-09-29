package payment

import "context"

// CreateRequest（创建支付请求）使用平台订单号，不把渠道订单号当业务主键。
type CreateRequest struct {
	OrderID string
	AccountID string
	SKU string
	AmountMinor int64
	Currency string
}

// PaymentIntent（支付意图）返回客户端调用渠道SDK所需短期参数。
type PaymentIntent struct { Channel string `json:"channel"`; Payload map[string]any `json:"payload"` }

// NotificationResult（支付回调结果）只有服务端验签成功后才能驱动钱包入账。
type NotificationResult struct {
	OrderID string
	ChannelOrderID string
	Paid bool
	AmountMinor int64
}

// Provider（支付提供者接口）隔离微信、Apple IAP、Google Play和其他渠道。
type Provider interface {
	ID() string
	CreatePayment(ctx context.Context,request CreateRequest)(PaymentIntent,error)
	VerifyNotification(ctx context.Context,headers map[string]string,body []byte)(NotificationResult,error)
	Query(ctx context.Context,orderID string)(NotificationResult,error)
}