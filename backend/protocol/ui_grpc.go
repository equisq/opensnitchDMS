package protocol

import (
	"context"

	"google.golang.org/grpc"
)

// Hand-written service glue for the UI service in ui.proto. The messages are
// in ui.pb.go; this is what protoc-gen-go-grpc would have emitted.

// UIServer is implemented by the OpenSnitch UI (this program). The daemon is
// the gRPC client.
type UIServer interface {
	Ping(context.Context, *PingRequest) (*PingReply, error)
	AskRule(context.Context, *Connection) (*Rule, error)
	// Subscribe is a unary call despite its name: the daemon sends its
	// config and receives the config the UI wants it to run with.
	Subscribe(context.Context, *ClientConfig) (*ClientConfig, error)
	Notifications(UI_NotificationsServer) error
	PostAlert(context.Context, *Alert) (*MsgResponse, error)
}

type UI_NotificationsServer interface {
	Send(*Notification) error
	Recv() (*NotificationReply, error)
	grpc.ServerStream
}

type uiNotificationsServer struct{ grpc.ServerStream }

func (x *uiNotificationsServer) Send(m *Notification) error { return x.ServerStream.SendMsg(m) }
func (x *uiNotificationsServer) Recv() (*NotificationReply, error) {
	m := new(NotificationReply)
	if err := x.ServerStream.RecvMsg(m); err != nil {
		return nil, err
	}
	return m, nil
}

func RegisterUIServer(s grpc.ServiceRegistrar, srv UIServer) {
	s.RegisterService(&UI_ServiceDesc, srv)
}

func pingHandler(srv any, ctx context.Context, dec func(any) error, ic grpc.UnaryServerInterceptor) (any, error) {
	in := new(PingRequest)
	if err := dec(in); err != nil {
		return nil, err
	}
	if ic == nil {
		return srv.(UIServer).Ping(ctx, in)
	}
	info := &grpc.UnaryServerInfo{Server: srv, FullMethod: "/protocol.UI/Ping"}
	return ic(ctx, in, info, func(ctx context.Context, req any) (any, error) {
		return srv.(UIServer).Ping(ctx, req.(*PingRequest))
	})
}

func askRuleHandler(srv any, ctx context.Context, dec func(any) error, ic grpc.UnaryServerInterceptor) (any, error) {
	in := new(Connection)
	if err := dec(in); err != nil {
		return nil, err
	}
	if ic == nil {
		return srv.(UIServer).AskRule(ctx, in)
	}
	info := &grpc.UnaryServerInfo{Server: srv, FullMethod: "/protocol.UI/AskRule"}
	return ic(ctx, in, info, func(ctx context.Context, req any) (any, error) {
		return srv.(UIServer).AskRule(ctx, req.(*Connection))
	})
}

func subscribeHandler(srv any, ctx context.Context, dec func(any) error, ic grpc.UnaryServerInterceptor) (any, error) {
	in := new(ClientConfig)
	if err := dec(in); err != nil {
		return nil, err
	}
	if ic == nil {
		return srv.(UIServer).Subscribe(ctx, in)
	}
	info := &grpc.UnaryServerInfo{Server: srv, FullMethod: "/protocol.UI/Subscribe"}
	return ic(ctx, in, info, func(ctx context.Context, req any) (any, error) {
		return srv.(UIServer).Subscribe(ctx, req.(*ClientConfig))
	})
}

func postAlertHandler(srv any, ctx context.Context, dec func(any) error, ic grpc.UnaryServerInterceptor) (any, error) {
	in := new(Alert)
	if err := dec(in); err != nil {
		return nil, err
	}
	if ic == nil {
		return srv.(UIServer).PostAlert(ctx, in)
	}
	info := &grpc.UnaryServerInfo{Server: srv, FullMethod: "/protocol.UI/PostAlert"}
	return ic(ctx, in, info, func(ctx context.Context, req any) (any, error) {
		return srv.(UIServer).PostAlert(ctx, req.(*Alert))
	})
}

func notificationsHandler(srv any, stream grpc.ServerStream) error {
	return srv.(UIServer).Notifications(&uiNotificationsServer{stream})
}

var UI_ServiceDesc = grpc.ServiceDesc{
	ServiceName: "protocol.UI",
	HandlerType: (*UIServer)(nil),
	Methods: []grpc.MethodDesc{
		{MethodName: "Ping", Handler: pingHandler},
		{MethodName: "AskRule", Handler: askRuleHandler},
		{MethodName: "Subscribe", Handler: subscribeHandler},
		{MethodName: "PostAlert", Handler: postAlertHandler},
	},
	Streams: []grpc.StreamDesc{
		{StreamName: "Notifications", Handler: notificationsHandler, ServerStreams: true, ClientStreams: true},
	},
	Metadata: "ui.proto",
}
