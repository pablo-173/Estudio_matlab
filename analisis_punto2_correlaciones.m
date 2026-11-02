%% FISIOLOGIA - PUNTO 2: CORRELACIONES DE VELOCIDAD LECTORA Y EOG
% Selecciona Base_EOG_punto1_actualizada.xlsx (hoja Participantes).
% Requiere Statistics and Machine Learning Toolbox para corr (p-values).
% Cada participante representa UNA observacion; no usa segmentos como sujetos.
clear; clc; close all;
[archivo,ruta] = uigetfile({'*.xlsx;*.csv','Base Excel o CSV (*.xlsx,*.csv)'}, ...
    'Selecciona la base unificada EOG (punto 1)');
if isequal(archivo,0), disp('Cancelado'); return; end
entrada = fullfile(ruta,archivo);
[~,~,ext] = fileparts(entrada);
if strcmpi(ext,'.csv')
    T=readtable(entrada,'TextType','string','VariableNamingRule','preserve');
else
    T=readtable(entrada,'Sheet','Participantes','TextType','string', ...
      'VariableNamingRule','preserve');
end
necesarias = ["ID","grupo","estado_analisis","duracion_lectura_s", ...
    "puntaje_15","pct_valido","mediana_fijaciones_ms", ...
    "mediana_sacadas_ms","tasa_sacadas_min"];
faltan = necesarias(~ismember(necesarias,string(T.Properties.VariableNames)));
if ~isempty(faltan)
    error('La base no tiene estas columnas: %s',strjoin(faltan,', '));
end
colsNumericas=["duracion_lectura_s","puntaje_15","pct_valido", ...
 "mediana_fijaciones_ms","mediana_sacadas_ms","tasa_sacadas_min"];
for j=1:numel(colsNumericas)
    v=colsNumericas(j);
    if ~isnumeric(T.(v)), T.(v)=str2double(string(T.(v))); end
end
T.ID=upper(regexprep(strtrim(string(T.ID)),'\s+',''));
T.grupo=upper(strtrim(string(T.grupo)));
T.estado_analisis=upper(strtrim(string(T.estado_analisis)));
excluidos=["EOG18","EOG19","EOG21","EOG26","EOG30","EOG32"];
T.estado_analisis(ismember(T.ID,excluidos))="EXCLUIDO";
T.estado_analisis(T.ID=="EOG36")="PENDIENTE";
T.velocidad_ppm=NaN(height(T),1);
okTiempo=isfinite(T.duracion_lectura_s)&T.duracion_lectura_s>0& ...
    T.duracion_lectura_s<1000;
T.velocidad_ppm(okTiempo)=521*60./T.duracion_lectura_s(okTiempo);
T.comprension_pct=T.puntaje_15*100/15;
T.calidad_baja=isfinite(T.pct_valido)&T.pct_valido<80;
B=T(T.estado_analisis=="INCLUIDO" & ismember(T.grupo,["A","B"]),:);
out=fullfile(ruta,'Resultados_Punto2_EOG');
if ~exist(out,'dir'),mkdir(out);end
writetable(B,fullfile(out,'00_base_analizada.csv'));
if exist('corr','file')~=2
    error(['Se requiere Statistics and Machine Learning Toolbox ', ...
        'para calcular Pearson/Spearman y p-valores. Instalala o activa la licencia.']);
end
variables=["mediana_fijaciones_ms","mediana_sacadas_ms", ...
  "tasa_sacadas_min","comprension_pct"];
nombres=["Duracion mediana de fijaciones (ms)", ...
    "Duracion mediana de sacadas (ms)","Tasa de sacadas (min-1)", ...
    "Comprension lectora (%)"];
grupos=["A","B","A+B"];
% Pearson y Spearman se reportan ambos; Spearman se toma como principal
% por la asimetria y los posibles valores extremos en EOG.
R=table('Size',[0 10], 'VariableTypes', ...
    {'string','string','double','double','double','double','double','double','double','double'}, ...
    'VariableNames',{'Variable','Grupo','n','rPearson','pPearson', ...
    'rhoSpearman','pSpearman','CI95_Pearson_inf','CI95_Pearson_sup','qBH_Spearman'});
for k=1:numel(variables)
  for z=1:numel(grupos)
    g=grupos(z);
    if g=="A+B", S=B; else, S=B(B.grupo==g,:);end
    x=S.velocidad_ppm; y=S.(variables(k));
    validos=isfinite(x)&isfinite(y); x=x(validos);y=y(validos);
    n=numel(x); rp=NaN;pp=NaN;rs=NaN;ps=NaN;ci=[NaN NaN];
    if n>=4 && numel(unique(x))>1 && numel(unique(y))>1
      [rp,pp]=corr(x,y,'Type','Pearson','Rows','complete');
      [rs,ps]=corr(x,y,'Type','Spearman','Rows','complete');
      if abs(rp)<1
        se=1/sqrt(n-3);ci=tanh(atanh(rp)+[-1,1]*1.9599639845*se);
      end
    end
    R=[R;{nombres(k),g,n,rp,pp,rs,ps,ci(1),ci(2),NaN}]; %#ok<AGROW>
  end
  % Una grafica para cada variable: A y B en colores distintos
  fig=figure('Visible','off','Color','w','Position',[80 80 850 550]); hold on;
  colores=[0.11 0.40 0.65;0.81 0.35 0.20];
  for z=1:2
    S=B(B.grupo==grupos(z),:);
    x=S.velocidad_ppm;y=S.(variables(k));
    valido=isfinite(x)&isfinite(y);x=x(valido);y=y(valido);
    scatter(x,y,65,colores(z,:),'filled','DisplayName',char("Grupo "+grupos(z)));
    if numel(x)>=3 && numel(unique(x))>1
      c=polyfit(x,y,1);xp=linspace(min(x),max(x),80);
      plot(xp,polyval(c,xp),'Color',colores(z,:),'LineWidth',1.5, ...
          'HandleVisibility','off');
    end
  end
  xlabel('Velocidad estimada por EOG (palabras/min)');ylabel(nombres(k));
  title('Velocidad vs '+nombres(k));legend('Location','best');grid on;box on;
  exportgraphics(fig,fullfile(out,sprintf('Figura_correlacion_%02d.png',k)), ...
    'Resolution',200);close(fig);
end
% BH separado dentro de cada grupo, para las 4 asociaciones exploradas.
for z=1:3
    ix=find(R.Grupo==grupos(z)&isfinite(R.pSpearman));
    if isempty(ix),continue;end
    [p,orden]=sort(R.pSpearman(ix));m=numel(p);
    q=p.*m./(1:m)';q=flipud(cummin(flipud(q)));q=min(q,1);
    R.qBH_Spearman(ix(orden))=q;
end
writetable(R,fullfile(out,'01_correlaciones_Pearson_Spearman.xlsx'));
S= B(~B.calidad_baja,:);
Q=table('Size',[0 5],'VariableTypes', ...
   {'string','string','double','double','double'}, ...
   'VariableNames',{'Variable','Grupo','nCalidad','rhoSpearman','pSpearman'});
for k=1:numel(variables)
 for z=1:3
  if grupos(z)=="A+B", U=S;else,U=S(S.grupo==grupos(z),:);end
  x=U.velocidad_ppm;y=U.(variables(k)); v=isfinite(x)&isfinite(y);
  x=x(v);y=y(v);rho=NaN;p=NaN;
  if numel(x)>=4 && numel(unique(x))>1 && numel(unique(y))>1
   [rho,p]=corr(x,y,'Type','Spearman');
  end
  Q=[Q;{nombres(k),grupos(z),numel(x),rho,p}]; %#ok<AGROW>
 end
end
writetable(Q,fullfile(out,'02_sensibilidad_calidad.xlsx'));
fid=fopen(fullfile(out,'LEEME_resultados.txt'),'w');
fprintf(fid,['PUNTO 2: correlaciones por participante.\n', ...
 'Datos: %d A+B (A=%d, B=%d). Se excluyen 6 EOG, EOG36 pendiente y controles.\n', ...
 'Spearman principal; Pearson complementario. qBH ajustado en cada grupo.\n', ...
 'Un resultado exploratorio no prueba causalidad.\n', ...
 'La velocidad es estimada de 521 palabras/intervalo EOG, sin cronometro.\n', ...
 'Calidad: sensibilidad con pct_valido >=80 cuando se informa.\n', ...
 'Punto 3 (Fisher) se evaluara por separado, no esta incluido aqui.\n'], ...
 height(B),sum(B.grupo=="A"),sum(B.grupo=="B"));fclose(fid);
disp(R);fprintf('\nResultados guardados en: %s\n',out);
