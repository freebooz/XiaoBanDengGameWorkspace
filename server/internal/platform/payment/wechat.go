package payment

import (
	"context"
	"errors"
)

// WeChatProvider（微信支付Provider）一期提供安全接口边界。
type WeChatProvider struct { AppID string; MchID string; APIV3Key string }

func (p *WeChatProvider) ID() string { return "wechat" }

func (p *WeChatProvider) CreatePayment(ctx context.Context,request CreateRequest)(PaymentIntent,error) {
	if p.AppID=="" || p.MchID=="" || p.APIV3Key=="" {
		return PaymentIntent{},errors.New("微信支付尚未配置真实商户参数")
	}
	return PaymentIntent{},errors.New("已预留微信支付接口；真实下单需接入微信支付API并完成商户联调")
}
func (p *WeChatProvider) VerifyNotification(ctx context.Context,headers map[string]string,body []byte)(NotificationResult,error) {
	return NotificationResult{},errors.New("真实微信支付回调必须使用平台证书和APIv3 Key验签后才能确认")
}
func (p *WeChatProvider) Query(ctx context.Context,orderID string)(NotificationResult,error) {
	return NotificationResult{},errors.New("真实微信支付查询需在商户配置完成后启用")
}