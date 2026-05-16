#property strict

input bool InpEnableDebugPrint  = false;
input int  InpMaxSessionLifeSec = 1800;
input int  InpEntryTickPeriod   = 0;

// ============================================================================
//  Session struct（値型 / ポインタ禁止 / -> 禁止）
// ============================================================================

struct CSimpleSession
{
   bool   active;

   string date;
   string time;
   int    hour;
   double bid;
   double ask;
   int    spread_points;
   double entry_mid;
   int    entry_direction;

   double   target_up;
   double   target_down;
   datetime start_time;

   int outcome_type;
   int outcome_time_sec;
   int direction_changes;

   double vol_1s;
   double vol_5s;
   double std_10ticks;

   double slope_10ticks;
   double slope_30ticks;

   int tick_density_1s;
   int tick_density_5s;

   int m1_direction;
   int m5_direction;

   double bb_width_m1;
   double adx_m5;

   double direction_agreement_10ticks;

   double rsi_m1;
   double distance_to_prev_high;
   double distance_to_prev_low;
};

// ============================================================================
//  グローバル（struct 配列ベース）
// ============================================================================

CSimpleSession g_sessions[];   // append-only
int            g_active_idx[]; // index list

string   g_file_name       = "PoC-0010_log.csv";
int      g_file_handle     = INVALID_HANDLE;
int      g_flush_counter   = 0;
datetime g_last_entry_second = 0;

// Tick 履歴
double   g_mid_history[];
datetime g_time_history[];
int      g_history_max = 10000;

// インジケータ
int g_handle_bb_m1  = INVALID_HANDLE;
int g_handle_adx_m5 = INVALID_HANDLE;
int g_handle_rsi_m1 = INVALID_HANDLE;

// ============================================================================
//  CSV Utility
// ============================================================================

string EscapeCsv(const string v)
{
   bool need_quote = false;
   if(StringFind(v, ",") >= 0 || StringFind(v, "\"") >= 0)
      need_quote = true;

   string out = "";
   int len = StringLen(v);
   for(int i=0;i<len;i++)
   {
      string ch = StringSubstr(v,i,1);
      if(ch=="\"") out += "\"\"";
      else out += ch;
   }
   if(need_quote) return "\"" + out + "\"";
   return out;
}

bool AppendLine(const string line)
{
   if(g_file_handle == INVALID_HANDLE) return false;

   FileSeek(g_file_handle,0,SEEK_END);
   FileWriteString(g_file_handle,line+"\r\n");

   g_flush_counter++;
   if(g_flush_counter>=100)
   {
      FileFlush(g_file_handle);
      g_flush_counter=0;
   }
   return true;
}

// ============================================================================
//  Utility
// ============================================================================

string FormatDate(datetime t)
{
   MqlDateTime dt; TimeToStruct(t,dt);
   return StringFormat("%04d-%02d-%02d",dt.year,dt.mon,dt.day);
}

string FormatTimeOnly(datetime t)
{
   MqlDateTime dt; TimeToStruct(t,dt);
   return StringFormat("%02d:%02d:%02d",dt.hour,dt.min,dt.sec);
}

bool GetPrevM1BidClose(double &out)
{
   out = iClose(_Symbol,PERIOD_M1,1);
   return (out!=0.0);
}

// Tick 履歴 push
void PushTick(const double mid,const datetime t)
{
   int sz = ArraySize(g_mid_history);
   ArrayResize(g_mid_history,sz+1);
   ArrayResize(g_time_history,sz+1);
   g_mid_history[sz]  = mid;
   g_time_history[sz] = t;

   sz++;
   if(sz > g_history_max)
   {
      int keep = g_history_max/2;
      if(keep<2000) keep=2000;

      int start = sz - keep;
      for(int i=0;i<keep;i++)
      {
         g_mid_history[i]  = g_mid_history[start+i];
         g_time_history[i] = g_time_history[start+i];
      }
      ArrayResize(g_mid_history,keep);
      ArrayResize(g_time_history,keep);
   }
}

// 直近 window 秒の max-min
double CalcVolSec(const datetime now,int window)
{
   int sz = ArraySize(g_mid_history);
   if(sz<=0) return 0.0;

   double mx=-DBL_MAX, mn=DBL_MAX;
   bool found=false;

   for(int i=sz-1;i>=0;i--)
   {
      if(now - g_time_history[i] > window) break;
      double m = g_mid_history[i];
      if(m>mx) mx=m;
      if(m<mn) mn=m;
      found=true;
   }
   if(!found) return 0.0;
   return mx-mn;
}

// 標準偏差（直近 n tick）
double CalcStdTicks(int n)
{
   int sz = ArraySize(g_mid_history);
   if(sz<n || n<=1) return 0.0;

   int st = sz-n;
   double sum=0.0;
   for(int i=st;i<sz;i++) sum+=g_mid_history[i];
   double mean = sum/n;

   double vs=0.0;
   for(int i=st;i<sz;i++)
   {
      double d = g_mid_history[i]-mean;
      vs += d*d;
   }
   return MathSqrt(vs/(n-1));
}

// 線形回帰傾き（直近 n tick）
double CalcSlopeTicks(int n)
{
   int sz = ArraySize(g_mid_history);
   if(sz<n || n<=1) return 0.0;

   int st = sz-n;
   double sx=0, sy=0, sxx=0, sxy=0;

   for(int i=0;i<n;i++)
   {
      double x=i;
      double y=g_mid_history[st+i];
      sx+=x; sy+=y; sxx+=x*x; sxy+=x*y;
   }
   double denom = n*sxx - sx*sx;
   if(denom==0) return 0.0;
   return (n*sxy - sx*sy)/denom;
}

// Tick density
int CalcTickDensity(const datetime now,int window)
{
   int sz = ArraySize(g_time_history);
   if(sz<=0) return 0;
   int c=0;
   for(int i=sz-1;i>=0;i--)
   {
      if(now - g_time_history[i] > window) break;
      c++;
   }
   return c;
}

// M1/M5 direction
int GetBarDir(ENUM_TIMEFRAMES tf)
{
   double o=iOpen(_Symbol,tf,1);
   double c=iClose(_Symbol,tf,1);
   if(o==0||c==0) return 0;
   if(c>o) return 1;
   if(c<o) return -1;
   return 0;
}

// BB width
double GetBBWidth()
{
   if(g_handle_bb_m1==INVALID_HANDLE) return 0.0;
   double up[1], lo[1];
   if(CopyBuffer(g_handle_bb_m1,0,1,1,up)<1) return 0.0;
   if(CopyBuffer(g_handle_bb_m1,1,1,1,lo)<1) return 0.0;
   return up[0]-lo[0];
}

// ADX
double GetADX()
{
   if(g_handle_adx_m5==INVALID_HANDLE) return 0.0;
   double buf[1];
   if(CopyBuffer(g_handle_adx_m5,0,1,1,buf)<1) return 0.0;
   return buf[0];
}

// RSI
double GetRSI()
{
   if(g_handle_rsi_m1==INVALID_HANDLE) return 0.0;
   double buf[1];
   if(CopyBuffer(g_handle_rsi_m1,0,1,1,buf)<1) return 0.0;
   return buf[0];
}

// 方向一致率（entry_direction と diff の符号一致率）
double CalcDirAgree(int n,int entry_dir)
{
   if(entry_dir==0) return 0.0;

   int sz = ArraySize(g_mid_history);
   if(sz<n+1) return 0.0;

   int st = sz-(n+1);
   int tot=0, ok=0;

   for(int i=st;i<st+n;i++)
   {
      double d = g_mid_history[i+1]-g_mid_history[i];
      if(d>0)
      {
         tot++; if(entry_dir>0) ok++;
      }
      else if(d<0)
      {
         tot++; if(entry_dir<0) ok++;
      }
   }
   if(tot==0) return 0.0;
   return (double)ok/(double)tot;
}

// 直近 window 秒の高値・安値距離
void CalcDistHL(const datetime now,int window,double entry_mid,double &dh,double &dl)
{
   int sz = ArraySize(g_mid_history);
   dh=0; dl=0;
   if(sz<=0) return;

   double mx=-DBL_MAX, mn=DBL_MAX;
   bool found=false;

   for(int i=sz-1;i>=0;i--)
   {
      if(now - g_time_history[i] > window) break;
      double m=g_mid_history[i];
      if(m>mx) mx=m;
      if(m<mn) mn=m;
      found=true;
   }
   if(!found) return;

   dh = mx - entry_mid;
   dl = entry_mid - mn;
}

// ============================================================================
//  LogSession
// ============================================================================

bool LogSession(const CSimpleSession &s,const string end_time)
{
   string line =
      EscapeCsv(s.date)+","+
      EscapeCsv(s.time)+","+
      IntegerToString(s.hour)+","+
      DoubleToString(s.bid,_Digits)+","+
      DoubleToString(s.ask,_Digits)+","+
      IntegerToString(s.spread_points)+","+
      DoubleToString(s.entry_mid,_Digits)+","+
      IntegerToString(s.entry_direction)+","+
      IntegerToString(s.outcome_type)+","+
      IntegerToString(s.outcome_time_sec)+","+
      IntegerToString(s.direction_changes)+","+
      EscapeCsv(end_time);

   line+=","+DoubleToString(s.vol_1s,5);
   line+=","+DoubleToString(s.vol_5s,5);
   line+=","+DoubleToString(s.std_10ticks,5);

   line+=","+DoubleToString(s.slope_10ticks,5);
   line+=","+DoubleToString(s.slope_30ticks,5);

   line+=","+IntegerToString(s.tick_density_1s);
   line+=","+IntegerToString(s.tick_density_5s);

   line+=","+IntegerToString(s.m1_direction);
   line+=","+IntegerToString(s.m5_direction);

   line+=","+DoubleToString(s.bb_width_m1,5);
   line+=","+DoubleToString(s.adx_m5,5);

   line+=","+DoubleToString(s.direction_agreement_10ticks,5);

   line+=","+DoubleToString(s.rsi_m1,5);
   line+=","+DoubleToString(s.distance_to_prev_high,5);
   line+=","+DoubleToString(s.distance_to_prev_low,5);

   return AppendLine(line);
}

// ============================================================================
//  StartSession（struct 値型で生成）
// ============================================================================

void StartSession(const MqlTick &tick,const datetime now,int entry_dir)
{
   CSimpleSession s;

   s.active = true;
   s.date   = FormatDate(now);
   s.time   = FormatTimeOnly(now);

   MqlDateTime dt; TimeToStruct(now,dt);
   s.hour = dt.hour;

   s.bid = tick.bid;
   s.ask = tick.ask;
   s.spread_points = (int)MathRound((tick.ask - tick.bid)/_Point);
   s.entry_mid = (tick.bid+tick.ask)/2.0;
   s.entry_direction = entry_dir;

   s.target_up   = s.entry_mid + 0.03;
   s.target_down = s.entry_mid - 0.03;
   s.start_time  = now;

   // 特徴量
   s.vol_1s      = CalcVolSec(now,1);
   s.vol_5s      = CalcVolSec(now,5);
   s.std_10ticks = CalcStdTicks(10);

   s.slope_10ticks = CalcSlopeTicks(10);
   s.slope_30ticks = CalcSlopeTicks(30);

   s.tick_density_1s = CalcTickDensity(now,1);
   s.tick_density_5s = CalcTickDensity(now,5);

   s.m1_direction = GetBarDir(PERIOD_M1);
   s.m5_direction = GetBarDir(PERIOD_M5);

   s.bb_width_m1 = GetBBWidth();
   s.adx_m5      = GetADX();

   s.direction_agreement_10ticks = CalcDirAgree(10,entry_dir);

   s.rsi_m1 = GetRSI();

   CalcDistHL(now,60,s.entry_mid,s.distance_to_prev_high,s.distance_to_prev_low);

   // append
   int idx = ArraySize(g_sessions);
   ArrayResize(g_sessions,idx+1);
   g_sessions[idx] = s;

   ArrayResize(g_active_idx,ArraySize(g_active_idx)+1);
   g_active_idx[ArraySize(g_active_idx)-1] = idx;
}

// ============================================================================
//  ProcessActiveSessions（struct 値コピー → 書き戻し）
// ============================================================================

void ProcessActiveSessions(double current_mid,datetime now)
{
   for(int k=ArraySize(g_active_idx)-1;k>=0;k--)
   {
      int idx = g_active_idx[k];
      CSimpleSession s = g_sessions[idx];

      if(!s.active)
      {
         int last=ArraySize(g_active_idx)-1;
         if(k!=last) g_active_idx[k]=g_active_idx[last];
         ArrayResize(g_active_idx,last);
         continue;
      }

      // timeout
      if(now - s.start_time > InpMaxSessionLifeSec)
      {
         s.outcome_type=0;
         s.outcome_time_sec=(int)(now - s.start_time);
         s.active=false;

         LogSession(s,FormatTimeOnly(now));

         g_sessions[idx]=s;

         int last=ArraySize(g_active_idx)-1;
         if(k!=last) g_active_idx[k]=g_active_idx[last];
         ArrayResize(g_active_idx,last);
         continue;
      }

      // first-touch
      int outcome=0;
      if(current_mid >= s.target_up) outcome=1;
      else if(current_mid <= s.target_down) outcome=-1;
      else continue;

      s.outcome_type=outcome;
      s.outcome_time_sec=(int)(now - s.start_time);
      s.active=false;

      LogSession(s,FormatTimeOnly(now));

      g_sessions[idx]=s;

      int last2=ArraySize(g_active_idx)-1;
      if(k!=last2) g_active_idx[k]=g_active_idx[last2];
      ArrayResize(g_active_idx,last2);
   }
}

// ============================================================================
//  OnTick
// ============================================================================

void OnTick()
{
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return;

   datetime now = tick.time;
   double mid = (tick.bid+tick.ask)/2.0;

   PushTick(mid,now);

   ProcessActiveSessions(mid,now);

   if(InpEntryTickPeriod>0)
   {
      if(now - g_last_entry_second < InpEntryTickPeriod) return;
   }
   g_last_entry_second = now;

   double prev;
   if(!GetPrevM1BidClose(prev)) return;

   int dir=0;
   if(mid>prev) dir=1;
   else if(mid<prev) dir=-1;
   else return;

   StartSession(tick,now,dir);
}

// ============================================================================
//  ForceCloseAllSessions
// ============================================================================

void ForceCloseAllSessions(datetime endt)
{
   for(int k=ArraySize(g_active_idx)-1;k>=0;k--)
   {
      int idx=g_active_idx[k];
      CSimpleSession s=g_sessions[idx];

      if(s.active)
      {
         s.outcome_type=0;
         s.outcome_time_sec=(int)(endt - s.start_time);
         s.active=false;
         LogSession(s,FormatTimeOnly(endt));
         g_sessions[idx]=s;
      }
   }
   ArrayResize(g_active_idx,0);
}

// ============================================================================
//  OnInit / OnDeinit
// ============================================================================

int OnInit()
{
   ArrayResize(g_sessions,0);
   ArrayResize(g_active_idx,0);
   ArrayResize(g_mid_history,0);
   ArrayResize(g_time_history,0);

   g_last_entry_second=0;

   g_file_handle = FileOpen(g_file_name,
      FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);

   if(g_file_handle==INVALID_HANDLE)
   {
      Print("FileOpen failed: ",GetLastError());
      return INIT_FAILED;
   }

   string header =
      "date,time,hour,bid,ask,spread_points,entry_mid,entry_direction,"
      "outcome_type,outcome_time_sec,direction_changes,end_time,"
      "vol_1s,vol_5s,std_10ticks,"
      "slope_10ticks,slope_30ticks,"
      "tick_density_1s,tick_density_5s,"
      "m1_direction,m5_direction,"
      "bb_width_m1,adx_m5,"
      "direction_agreement_10ticks,"
      "rsi_m1,distance_to_prev_high,distance_to_prev_low";

   FileWriteString(g_file_handle,header+"\r\n");

   g_handle_bb_m1  = iBands(_Symbol,PERIOD_M1,20,2.0,0,PRICE_CLOSE);
   g_handle_adx_m5 = iADX(_Symbol,PERIOD_M5,14);
   g_handle_rsi_m1 = iRSI(_Symbol,PERIOD_M1,14,PRICE_CLOSE);

   if(g_handle_bb_m1 == INVALID_HANDLE)
      Print("iBands handle creation failed: ", GetLastError());
   if(g_handle_adx_m5 == INVALID_HANDLE)
      Print("iADX handle creation failed: ", GetLastError());
   if(g_handle_rsi_m1 == INVALID_HANDLE)
      Print("iRSI handle creation failed: ", GetLastError());

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   ForceCloseAllSessions(TimeCurrent());

   if(g_file_handle != INVALID_HANDLE)
   {
      FileFlush(g_file_handle);
      FileClose(g_file_handle);
      g_file_handle = INVALID_HANDLE;
   }

   if(g_handle_bb_m1 != INVALID_HANDLE)
   {
      IndicatorRelease(g_handle_bb_m1);
      g_handle_bb_m1 = INVALID_HANDLE;
   }

   if(g_handle_adx_m5 != INVALID_HANDLE)
   {
      IndicatorRelease(g_handle_adx_m5);
      g_handle_adx_m5 = INVALID_HANDLE;
   }

   if(g_handle_rsi_m1 != INVALID_HANDLE)
   {
      IndicatorRelease(g_handle_rsi_m1);
      g_handle_rsi_m1 = INVALID_HANDLE;
   }
}
