# Genera las graficas del reporte a partir de load/resultados (requiere matplotlib).
# Uso: python3 load/graficas.py
import re, collections
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import os
BASE=os.path.dirname(os.path.abspath(__file__))
R=os.path.join(BASE,"resultados")+"/"
OUT=os.path.join(BASE,"graficas")+"/"
os.makedirs(OUT,exist_ok=True)
NAVY="#1f3a5f"; TEAL="#2a7f8e"; GRAY="#5c687a"; RED="#b5443b"; AMB="#c98a1a"
plt.rcParams.update({"font.family":"Helvetica","font.size":9,"axes.edgecolor":"#9aa5b4","axes.labelcolor":NAVY,
  "xtick.color":GRAY,"ytick.color":GRAY,"axes.spines.top":False,"axes.spines.right":False,"axes.grid":True,"grid.color":"#e3e8ef","grid.linewidth":0.7})

# ---------------- A: ruptura por escalón (tabla 2 del documento)
vus=[200,400,600,800,1000,1200,1400,1600,1800,2000]
avg=[2.8,5.0,19.0,78.9,124.6,166.7,205.3,242.7,281.6,319.4]
p95=[5.4,12.9,56.4,140.8,186.2,229.5,272.3,306.0,346.1,385.9]
p99=[9.3,37.1,95.8,176.9,219.2,266.7,310.0,342.7,385.6,421.2]
rps=[1830,3689,4929,4400,4396,4453,4546,4633,4684,4742]
fig,(a1,a2)=plt.subplots(1,2,figsize=(9.2,3.5))
a1.plot(vus,avg,"-o",color=TEAL,label="Promedio",ms=4); a1.plot(vus,p95,"-o",color=NAVY,label="p95",ms=4); a1.plot(vus,p99,"-o",color=AMB,label="p99",ms=4)
a1.axhline(500,color=RED,ls="--",lw=1); a1.text(210,512,"criterio p95 < 500 ms",color=RED,fontsize=8)
a1.axvline(800,color=GRAY,ls=":",lw=1); a1.text(820,380,"800 usuarios",color=GRAY,fontsize=8,va="top")
a1.set_xlabel("Usuarios virtuales concurrentes"); a1.set_ylabel("Latencia (ms)"); a1.set_ylim(0,560); a1.legend(frameon=False,loc="upper left",bbox_to_anchor=(0.0,0.88),fontsize=8)
a1.set_title("Latencia por escalón",color=NAVY,fontsize=10,loc="left")
a2.bar(vus,rps,width=140,color=TEAL); a2.axvline(800,color=GRAY,ls=":",lw=1); a2.text(820,5450,"800 usuarios",color=GRAY,fontsize=8,va="top")
a2.set_xlabel("Usuarios virtuales concurrentes"); a2.set_ylabel("Peticiones por segundo"); a2.set_ylim(0,5600)
a2.set_title("Rendimiento por escalón",color=NAVY,fontsize=10,loc="left")
fig.tight_layout(); fig.savefig(OUT+"graf-ruptura.png",dpi=200); plt.close(fig)

# ---------------- B y C: recursos desde docker stats
def leer(nombre):
    datos=collections.defaultdict(lambda:{"t":[],"cpu":[],"mem":[]}); t=None; t0=None
    for l in open(R+nombre):
        l=l.strip()
        m=re.match(r"^(\d\d):(\d\d):(\d\d)$",l)
        if m:
            t=int(m[1])*3600+int(m[2])*60+int(m[3]); t0=t0 if t0 is not None else t; continue
        p=l.split()
        if len(p)>=3 and p[0].startswith("recetarapida"):
            mm=re.match(r"([\d.]+)(MiB|GiB)",p[2]); mem=float(mm[1])*(1024 if mm[2]=="GiB" else 1)
            d=datos[p[0].replace("recetarapida-","")]; d["t"].append((t-t0)/60); d["cpu"].append(float(p[1].rstrip("%"))); d["mem"].append(mem)
    return datos
col={"gateway":NAVY,"prescription":TEAL,"auth":AMB,"postgres":RED}
nom={"gateway":"Gateway","prescription":"Prescripciones","auth":"Autenticación","postgres":"PostgreSQL"}
rup=leer("recursos-ruptura.log")
fig,(b1,b2)=plt.subplots(1,2,figsize=(9.2,3.8))
for k in ["gateway","prescription","auth","postgres"]:
    b1.plot(rup[k]["t"],rup[k]["cpu"],color=col[k],label=nom[k],lw=1.4); b2.plot(rup[k]["t"],rup[k]["mem"],color=col[k],label=nom[k],lw=1.4)
b1.axhline(600,color=RED,ls="--",lw=1); b1.text(0.1,612,"límite: 6 CPU",color=RED,fontsize=8)
b1.set_xlabel("Tiempo (min)"); b1.set_ylabel("CPU (% de un núcleo)"); b1.set_ylim(0,680); b1.legend(frameon=False,loc="upper center",bbox_to_anchor=(0.5,-0.22),ncol=4,fontsize=8)
b1.set_title("CPU durante la ruptura",color=NAVY,fontsize=10,loc="left")
b2.set_xlabel("Tiempo (min)"); b2.set_ylabel("Memoria (MiB)"); b2.set_title("Memoria durante la ruptura",color=NAVY,fontsize=10,loc="left")
b2.axhline(1024,color=RED,ls="--",lw=1); b2.text(0.1,1035,"límite de prescripciones: 1 GiB",color=RED,fontsize=8); b2.set_ylim(0,1150)
fig.tight_layout(); fig.savefig(OUT+"graf-recursos-ruptura.png",dpi=200); plt.close(fig)

car=leer("recursos-carga.log"); pic=leer("recursos-pico.log")
fig,(c1,c2)=plt.subplots(1,2,figsize=(9.2,3.2),sharey=True)
for ax,dat,tit in ((c1,car,"CPU en la carga sostenida"),(c2,pic,"CPU en el pico")):
    for k in ["gateway","prescription","auth","postgres"]:
        ax.plot(dat[k]["t"],dat[k]["cpu"],color=col[k],label=nom[k],lw=1.4)
    ax.set_xlabel("Tiempo (min)"); ax.set_title(tit,color=NAVY,fontsize=10,loc="left")
c1.set_ylabel("CPU (% de un núcleo)"); c1.legend(frameon=False,fontsize=8)
fig.tight_layout(); fig.savefig(OUT+"graf-recursos-carga-pico.png",dpi=200); plt.close(fig)
print({k:(max(v["cpu"]),round(max(v["mem"]))) for k,v in rup.items()})
