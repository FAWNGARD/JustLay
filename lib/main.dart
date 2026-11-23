import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
void main()=>runApp(const JustLay());
const lime=Color(0xffb5f56e), dark=Color(0xff14141b);
class JustLay extends StatelessWidget{const JustLay({super.key});@override Widget build(BuildContext c)=>MaterialApp(debugShowCheckedModeBanner:false,theme:ThemeData.dark().copyWith(scaffoldBackgroundColor:dark),home:Platform.isWindows?const Server():const Remote());}
class Win{
 static final dll=DynamicLibrary.open('user32.dll');
 static final void Function(int,int,int,int) keyEvent=dll.lookupFunction<Void Function(Uint8,Uint8,Uint32,UintPtr),void Function(int,int,int,int)>('keybd_event');
 static final void Function(int,int,int,int,int) mouseEvent=dll.lookupFunction<Void Function(Uint32,Uint32,Uint32,Uint32,UintPtr),void Function(int,int,int,int,int)>('mouse_event');
 static void key(int k,bool down)=>keyEvent(k,0,down?0:2,0);
 static void move(int x,int y)=>mouseEvent(1,x&0xffffffff,y&0xffffffff,0,0);
 static void button(bool right,bool down)=>mouseEvent(right?(down?8:16):(down?2:4),0,0,0,0);
 static void scroll(int n)=>mouseEvent(0x800,0,0,n&0xffffffff,0);
}
class Server extends StatefulWidget{const Server({super.key});@override State<Server> createState()=>_Server();}
class _Server extends State<Server>{
 HttpServer? server;final sockets=<WebSocket>{},keys=<int>{};String address='Detecting…',status='Starting…';late final String pin;
 @override void initState(){super.initState();pin=(100000+Random.secure().nextInt(900000)).toString();start();}
 Future<void> start()async{try{
 final nets=await NetworkInterface.list(type:InternetAddressType.IPv4);final ips=nets.expand((n)=>n.addresses).where((a)=>!a.isLoopback).toList();
 final local=ips.where((a)=>a.address.startsWith('192.168.')||a.address.startsWith('10.')||RegExp(r'^172\.(1[6-9]|2[0-9]|3[01])\.').hasMatch(a.address)).toList();
 address=(local.isNotEmpty?local.first:ips.isNotEmpty?ips.first:null)?.address??'Unknown';
 server=await HttpServer.bind(InternetAddress.anyIPv4,8765);setState(()=>status='Waiting for phone');
 server!.listen((request)async{
 if(!WebSocketTransformer.isUpgradeRequest(request)){request.response.statusCode=400;await request.response.close();return;}
 final ws=await WebSocketTransformer.upgrade(request);sockets.add(ws);bool auth=false;
 ws.listen((raw){try{final m=jsonDecode(raw as String) as Map<String,dynamic>;final t=m['type'];
 if(!auth){if(t=='auth'&&m['pin']==pin){auth=true;ws.add('{"type":"ok"}');setState(()=>status='Connected');}else{ws.add('{"type":"error"}');ws.close();}return;}
 if(t=='key'){final k=(m['vk'] as num).toInt();if(k<1||k>255)return;final down=m['down']==true;if(down){if(keys.add(k))Win.key(k,true);}else{keys.remove(k);Win.key(k,false);}}
 if(t=='move')Win.move((m['dx'] as num).round().clamp(-150,150).toInt(),(m['dy'] as num).round().clamp(-150,150).toInt());
 if(t=='click')Win.button(m['right']==true,m['down']==true);
 if(t=='scroll')Win.scroll((m['amount'] as num).round().clamp(-1200,1200).toInt());
 }catch(_){}},onDone:(){sockets.remove(ws);release();if(mounted)setState(()=>status='Waiting for phone');},onError:(_){sockets.remove(ws);release();});
 });
 }catch(e){if(mounted)setState(()=>status='Error: $e');}}
 void release(){for(final k in keys.toList())Win.key(k,false);keys.clear();Win.button(false,false);Win.button(true,false);}
 @override void dispose(){release();for(final s in sockets)s.close();server?.close(force:true);super.dispose();}
 @override Widget build(BuildContext c)=>Scaffold(body:Center(child:Padding(padding:const EdgeInsets.all(28),child:Column(mainAxisSize:MainAxisSize.min,children:[const Text('JustLay',style:TextStyle(fontSize:48,color:lime,fontWeight:FontWeight.bold)),const SizedBox(height:24),SelectableText('IP: $address:8765',style:const TextStyle(fontSize:22)),const SizedBox(height:16),SelectableText('PIN: $pin',style:const TextStyle(fontSize:34)),const SizedBox(height:24),Text(status),const SizedBox(height:24),const Text('Use the same Wi-Fi. Allow private-network access in Windows Firewall.',textAlign:TextAlign.center)]))));
}
class Remote extends StatefulWidget{const Remote({super.key});@override State<Remote> createState()=>_Remote();}
class _Remote extends State<Remote>{
 final ip=TextEditingController(),pin=TextEditingController();WebSocket? ws;bool connected=false;String error='';int tab=0;final held=<int>{};Offset? last;
 void send(Map<String,dynamic> m){if(connected)ws?.add(jsonEncode(m));}
 Future<void> connect()async{try{final host=ip.text.trim().replaceAll(RegExp(r'^wss?://'),'').replaceAll(RegExp(r':8765/?$'),'');final s=await WebSocket.connect('ws://$host:8765').timeout(const Duration(seconds:6));ws=s;s.listen((raw){final m=jsonDecode(raw as String);if(m['type']=='ok'){if(mounted)setState(()=>connected=true);}else{if(mounted)setState(()=>error='Wrong PIN');s.close();}},onDone:disconnect,onError:(_)=>disconnect());s.add(jsonEncode({'type':'auth','pin':pin.text.trim()}));}catch(_){if(mounted)setState(()=>error='Connection failed. Check IP and firewall.');}}
 void disconnect(){for(final k in held.toList())send({'type':'key','vk':k,'down':false});held.clear();ws?.close();ws=null;if(mounted)setState(()=>connected=false);}
 void key(int vk,bool down){if(down){if(!held.add(vk))return;}else{held.remove(vk);}send({'type':'key','vk':vk,'down':down});}
 @override void dispose(){disconnect();ip.dispose();pin.dispose();super.dispose();}
 Widget hold(String label,int vk)=>Listener(onPointerDown:(_)=>key(vk,true),onPointerUp:(_)=>key(vk,false),onPointerCancel:(_)=>key(vk,false),child:Container(width:67,height:67,margin:const EdgeInsets.all(3),alignment:Alignment.center,decoration:BoxDecoration(color:const Color(0xff292933),borderRadius:BorderRadius.circular(16)),child:Text(label,style:const TextStyle(fontSize:17,fontWeight:FontWeight.bold))));
 void click(bool right){send({'type':'click','right':right,'down':true});Future.delayed(const Duration(milliseconds:70),()=>send({'type':'click','right':right,'down':false}));}
 Widget touch()=>Column(children:[Expanded(child:GestureDetector(behavior:HitTestBehavior.opaque,onPanStart:(d)=>last=d.localPosition,onPanUpdate:(d){final p=d.localPosition;if(last!=null){final v=(p-last!)*1.5;send({'type':'move','dx':v.dx.round(),'dy':v.dy.round()});}last=p;},onPanEnd:(_)=>last=null,onTap:()=>click(false),child:Container(width:double.infinity,decoration:BoxDecoration(color:const Color(0xff292933),borderRadius:BorderRadius.circular(22)),alignment:Alignment.center,child:const Text('DRAG TO MOVE · TAP TO CLICK'))),const SizedBox(height:12),Row(children:[Expanded(child:ElevatedButton(onPressed:()=>click(false),child:const Text('LEFT'))),Expanded(child:ElevatedButton(onPressed:()=>click(true),child:const Text('RIGHT')))]),Row(children:[Expanded(child:ElevatedButton(onPressed:()=>send({'type':'scroll','amount':120}),child:const Text('SCROLL UP'))),Expanded(child:ElevatedButton(onPressed:()=>send({'type':'scroll','amount':-120}),child:const Text('SCROLL DOWN')))])]);
 Widget pad()=>Column(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[const Text('ARROWS · SPACE · Z · X · ENTER · ESC'),Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[Column(children:[hold('↑',38),Row(children:[hold('←',37),hold('↓',40),hold('→',39)])]),Column(children:[Row(children:[hold('Z',90),hold('X',88)]),Row(children:[hold('SPACE',32),hold('ENTER',13)])])]),Row(mainAxisAlignment:MainAxisAlignment.center,children:[hold('ESC',27),hold('SHIFT',16)])]);
 @override Widget build(BuildContext c)=>Scaffold(body:SafeArea(child:Padding(padding:const EdgeInsets.all(14),child:Column(children:[const Text('JustLay',style:TextStyle(fontSize:30,color:lime,fontWeight:FontWeight.bold)),const SizedBox(height:12),if(!connected)...[TextField(controller:ip,decoration:const InputDecoration(labelText:'PC IP address')),TextField(controller:pin,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'6-digit PIN')),ElevatedButton(onPressed:connect,child:const Text('CONNECT')),Text(error)]else...[Row(children:[Expanded(child:ElevatedButton(onPressed:()=>setState(()=>tab=0),child:const Text('TOUCHPAD'))),Expanded(child:ElevatedButton(onPressed:()=>setState(()=>tab=1),child:const Text('PLATFORMER'))),IconButton(onPressed:disconnect,icon:const Icon(Icons.link_off))]),Expanded(child:tab==0?touch():pad())]]))));
}