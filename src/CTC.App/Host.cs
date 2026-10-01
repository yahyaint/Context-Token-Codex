// SPDX-License-Identifier: MIT
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using CTC.Core;

namespace CTC.App;
public sealed class Host:IDisposable
{
    private readonly MonitorService monitor;
    private readonly QuotaProvider provider;
    private readonly CancellationTokenSource stop=new();
    private readonly string data;
    private readonly string home;
    private readonly bool fixture;
    private string stamp="";
    private int refreshing;
    private readonly object estimateLock=new();
    private DateTimeOffset nextQuota;
    private QuotaEstimator estimator=new();
    public MonitorSnapshot? Snapshot {get;private set;}
    public QuotaSnapshot? Quota {get;private set;}
    public string Error {get;private set;}="";
    public event Action? Changed;
    public Host(string home,string data,bool fixture=false){this.home=home;this.data=data;this.fixture=fixture;monitor=new(home);provider=new(home,data);}
    public Task Start()=>Task.Run(async()=>
    {
        try{while(!stop.IsCancellationRequested)
        {
            try
            {
                Snapshot=monitor.Read();
                string current=QuotaProvider.ProfileStamp(home);
                if(current!=stamp){stamp=current;Quota=null;lock(estimateLock)estimator=new(){Scope=stamp};nextQuota=default;}
                if(DateTimeOffset.Now>=nextQuota)_=Refresh();
                Changed?.Invoke();
            }
            catch(Exception e) when(e is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException){Error=e.Message;Changed?.Invoke();}
            try{await Task.Delay(1000,stop.Token);}catch(OperationCanceledException){break;}
        }}finally{monitor.Dispose();}
    },stop.Token);
    public string Share(string id){lock(estimateLock)return estimator.Share(id,DateTimeOffset.Now);}
    public async Task Refresh()
    {
        if(Interlocked.CompareExchange(ref refreshing,1,0)!=0)return;nextQuota=DateTimeOffset.Now.AddSeconds(30);
        try
        {
            QuotaSnapshot quota;
            if(fixture)
            {
                using var doc=System.Text.Json.JsonDocument.Parse(File.ReadAllText(Path.Combine(home,"quota-fixture.json")));
                quota=QuotaProvider.Parse(doc.RootElement,"Fixture",DateTimeOffset.Now,stamp);
            }
            else quota=await provider.ReadAsync(stop.Token);
            if(quota.ProfileStamp!=stamp)return;
            string scope=stamp+"-"+quota.AccountKey;
            string ledger=Path.Combine(data,"quota-native-"+scope+".json");
            lock(estimateLock)
            {
                if(estimator.Scope!=scope)estimator=QuotaEstimator.Load(ledger,scope);
                estimator.Update(quota,Snapshot?.Events??[],Path.Combine(AppContext.BaseDirectory,"Quota.Rates.json"),DateTimeOffset.Now);
                AtomicFile.Json(ledger,estimator);
            }
            Quota=quota;Error="";
        }
        catch(Exception e) when(e is IOException or TimeoutException or UnauthorizedAccessException or OperationCanceledException or System.ComponentModel.Win32Exception){if(!stop.IsCancellationRequested)Error=e.Message;nextQuota=DateTimeOffset.Now.AddSeconds(15);}
        finally{Interlocked.Exchange(ref refreshing,0);Changed?.Invoke();}
    }
    public void Dispose()=>stop.Cancel();
}
