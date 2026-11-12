#!/usr/bin/env python3
"""Synthetic stateful HTTP fixture for native UI tests only. Never bundled or deployed."""
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
import json
import threading

MOVIE = {'id':'manual:ui_fixture_seen','title':'仅用于界面测试的电影','year':2020,'originalTitle':'','runtime':95,'poster':'','aliases':[],'tags':{},'source':'manual','revision':1}
NEXT = dict(MOVIE,id='manual:ui_fixture_next',title='仅用于界面测试的下一部',year=2021)
TOKEN='synthetic-native-ui-session-20261112'
state={'movies':{MOVIE['id']:MOVIE},'records':{},'mutations':{},'active':False}
lock=threading.RLock()
class Handler(BaseHTTPRequestHandler):
    def log_message(self,*args):pass
    def respond(self,status,data):
        encoded=json.dumps(data,ensure_ascii=False).encode()
        self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Content-Length',str(len(encoded)));self.end_headers();self.wfile.write(encoded)
    def handle_request(self):
        with lock:
            path=self.path.split('?')[0]
            length=int(self.headers.get('Content-Length',0))
            if length>65536:self.respond(400,{});return
            data=json.loads(self.rfile.read(length)) if length else {}
            if path=='/health':self.respond(200,{'ok':True});return
            if self.command!='GET' and self.headers.get('X-MovieMind')!='1':self.respond(403,{});return
            if path=='/api/auth/login':
                if data!={'name':'fixture_user','password':'synthetic-ui-password-731'}:self.respond(403,{});return
                state['active']=True;state['records'].clear();state['mutations'].clear();self.respond(200,{'userId':'fixture-ui-user','token':TOKEN});return
            if path=='/api/auth/logout':state['active']=False;self.respond(200,{'ok':True});return
            if self.headers.get('Authorization')!='Bearer '+TOKEN or not state['active']:self.respond(401,{});return
            if self.headers.get('X-MovieMind-Account')!='fixture-ui-user':self.respond(403,{});return
            if path=='/api/me':self.respond(200,{'userId':'fixture-ui-user','preferences':{'likes':[],'hardAvoid':[],'ratingAnchor':None,'revision':0},'externalCatalogConfigured':False});return
            if path=='/api/movies':self.respond(200,list(state['movies'].values()));return
            if path=='/api/records':self.respond(200,list(state['records'].values()));return
            if path=='/api/pair':self.respond(200,{'paired':False});return
            if path=='/api/recommend':self.respond(200,{'candidates':[{'movie':NEXT,'label':'值得尝试','reasons':['根据明确反馈筛选；此内容仅用于界面测试'],'gaps':[]}],'pending':[],'mode':'rules','hasMore':False});return
            if path.startswith('/api/movies/') and self.command=='PUT':
                data['revision']=1;state['movies'][data['id']]=data;self.respond(200,data);return
            if path.startswith('/api/records/') and self.command=='PUT':
                mutation=data['mutationId']
                if mutation in state['mutations']:self.respond(200,state['mutations'][mutation]);return
                record=data['record'];old=state['records'].get(record['movieId'],{})
                if data['expectedRevision']!=old.get('revision',0):self.respond(409,{'current':old});return
                record=dict(record,revision=old.get('revision',0)+1)
                state['records'][record['movieId']]=record
                reply=dict(record,mutationId=mutation);state['mutations'][mutation]=reply;self.respond(200,reply);return
            self.respond(404,{})
    do_GET=handle_request
    do_POST=handle_request
    do_PUT=handle_request
    do_DELETE=handle_request
if __name__=='__main__':ThreadingHTTPServer(('127.0.0.1',18089),Handler).serve_forever()
