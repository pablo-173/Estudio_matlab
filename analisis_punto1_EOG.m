%% PUNTO 1 - COMPARACION GRUPOS A Y B (FISIOLOGIA, UVG)
% Selecciona Base_EOG_punto1_actualizada.xlsx cuando se solicite.
% MATLAB base: readtable, writetable, histogram, graficas basicas.
% Estadistica inferencial: Statistics and Machine Learning Toolbox.
% Recomendado MATLAB R2021b o posterior.
clear; clc; close all;
[archivo,ruta] = uigetfile({'*.xlsx','Libro de Excel (*.xlsx)'}, ...
    'Selecciona Base_EOG_punto1_actualizada.xlsx');
if isequal(archivo,0), disp('Seleccion cancelada.'); return; end
T = readtable(fullfile(ruta,archivo),'Sheet','Participantes', ...
    'VariableNamingRule','preserve','TextType','string');
out = fullfile(ruta,'Resultados_Punto1_EOG');
if ~exist(out,'dir'), mkdir(out); end
% Verificar columnas esenciales
cols = ["ID","grupo","estado_analisis","puntaje_15", ...
        "duracion_lectura_s","pct_valido","num_sacadas", ...
        "num_fijaciones","tasa_sacadas_min","tasa_fijaciones_min", ...
        "mediana_sacadas_ms","mediana_fijaciones_ms"];
faltantes = cols(~ismember(cols,string(T.Properties.VariableNames)));
if ~isempty(faltantes), error('Faltan columnas: %s',strjoin(faltantes,', ')); end
numericCols = ["puntaje_15","duracion_lectura_s","pct_valido", ...
    "num_sacadas","num_fijaciones","tasa_sacadas_min", ...
    "tasa_fijaciones_min","mediana_sacadas_ms","mediana_fijaciones_ms"];
for c=numericCols
    if ~isnumeric(T.(c)), T.(c)=str2double(string(T.(c))); end
end
T.ID = upper(strtrim(string(T.ID)));
T.grupo = strtrim(string(T.grupo));
T.estado_analisis = upper(strtrim(string(T.estado_analisis)));
% Exclusiones redundantes para evitar inclusión accidental
excluidos = ["EOG18","EOG19","EOG21","EOG26","EOG30","EOG32"];
T.estado_analisis(ismember(T.ID,excluidos)) = "EXCLUIDO";
T.estado_analisis(T.ID=="EOG36")="PENDIENTE";
T.velocidad_ppm = NaN(height(T),1);
validoTiempo = isfinite(T.duracion_lectura_s) & T.duracion_lectura_s>0 ...
    & T.duracion_lectura_s<1000;
T.velocidad_ppm(validoTiempo) = 521*60./T.duracion_lectura_s(validoTiempo);
T.comprension_pct = T.puntaje_15*100/15;
T.calidad_baja = isfinite(T.pct_valido) & T.pct_valido<80;
base = T(T.estado_analisis=="INCLUIDO" & ismember(T.grupo,["A","B"]),:);
writetable(base,fullfile(out,'base_analizada_A_B.csv'));
writetable(T,fullfile(out,'auditoria_todos_registros.csv'));
fprintf('\nTotal original: %d | Excluidos: %d | Pendientes: %d\n', ...
   height(T),sum(T.estado_analisis=="EXCLUIDO"),sum(T.estado_analisis=="PENDIENTE"));
fprintf('A: %d | B: %d | total A+B: %d\n',sum(base.grupo=="A"), ...
    sum(base.grupo=="B"),height(base));
fprintf('Baja calidad (<80%%): %s\n',strjoin(base.ID(base.calidad_baja),', '));
% Variables de comparacion: cada participante es una observacion
variables = ["velocidad_ppm","comprension_pct","mediana_fijaciones_ms", ...
    "mediana_sacadas_ms","tasa_fijaciones_min","tasa_sacadas_min", ...
    "num_sacadas","num_fijaciones"];
nombres = ["Velocidad lectora estimada (ppm)","Comprension (%)", ...
    "Mediana de fijaciones (ms)","Mediana de sacadas (ms)", ...
    "Tasa de fijaciones (min-1)","Tasa de sacadas (min-1)", ...
    "Numero de sacadas","Numero de fijaciones"];
% Herramienta de estadistica - necesaria para inferencia
hayStats = exist('ttest2','file')==2 && exist('ranksum','file')==2;
if ~hayStats
 warning(['Statistics and Machine Learning Toolbox no disponible: ', ...
    'se calcularan descriptivas y graficas, pero no p-valores.']);
end
% Una fila por grupo por variable
D=table('Size',[0 10],'VariableTypes', ...
    {'string','string','double','double','double','double','double','double','double','double'}, ...
    'VariableNames',{'Variable','Grupo','n','Media','DE','Mediana','Q1','Q3','Min','Max'});
R=table('Size',[0 11],'VariableTypes', ...
    {'string','double','double','double','double','double','double','double','double','double','double'}, ...
    'VariableNames',{'Variable','nA','nB','DiferenciaMedias_AmenosB','CI95_inf','CI95_sup', ...
    'pWelch','pMannWhitney','Hedges_g','pPrincipal','q_BH'});
for k=1:numel(variables)
    v=variables(k); a=base.(v)(base.grupo=="A");b=base.(v)(base.grupo=="B");
    a=a(isfinite(a));b=b(isfinite(b));
    for g=["A","B"]
        if g=="A", x=a;else,x=b;end
        if isempty(x)
          D=[D;{nombres(k),g,0,NaN,NaN,NaN,NaN,NaN,NaN,NaN}]; %#ok<AGROW>
        else
          D=[D;{nombres(k),g,numel(x),mean(x),std(x),median(x), ...
                prctile_local(x,25),prctile_local(x,75),min(x),max(x)}]; %#ok<AGROW>
        end
    end
    pW=NaN; pMW=NaN; ci=[NaN NaN];gH=NaN;
    if numel(a)>=3 && numel(b)>=3 && hayStats
      try
        [~,pW,ci]=ttest2(a,b,'Vartype','unequal');
        pMW=ranksum(a,b);
      catch ME
        warning('Error al comparar %s: %s',v,ME.message);
      end
      sP=sqrt(((numel(a)-1)*var(a)+(numel(b)-1)*var(b))/(numel(a)+numel(b)-2));
      if sP>0
         d=(mean(a)-mean(b))/sP;
         gH=d*(1-3/(4*(numel(a)+numel(b))-9));
      end
    end
    % Prueba principal: Welch para diferencias de medias. Mann-Whitney como sensibilidad.
    R=[R;{nombres(k),numel(a),numel(b),mean(a)-mean(b), ...
        ci(1),ci(2),pW,pMW,gH,pW,NaN}]; %#ok<AGROW>
    % Graficas: puntos de cada sujeto + media, sin funciones estadisticas extra
    fig=figure('Visible','off','Color','w','Position',[100 100 740 490]);
    hold on;
    rng(2026+k);
    scatter(1+(rand(size(a))-.5)*.18,a,42,[0.12 .40 .56],'filled');
    scatter(2+(rand(size(b))-.5)*.18,b,42,[.77 .36 .25],'filled');
    if ~isempty(a),plot(1,mean(a),'kd','MarkerFaceColor','k','MarkerSize',10);end
    if ~isempty(b),plot(2,mean(b),'kd','MarkerFaceColor','k','MarkerSize',10);end
    xlim([.5,2.5]); xticks([1 2]);xticklabels({'A: iniciales','B: avanzados'});
    ylabel(nombres(k));title("Comparacion: " + nombres(k));grid on;box on;
    exportgraphics(fig,fullfile(out,sprintf('Figura_%02d.png',k)),'Resolution',180);
    close(fig);
end
% Benjamini-Hochberg sobre las 7 comparaciones principales; recuento de fijaciones exploratorio
ix=find(isfinite(R.pPrincipal(1:7)));
if ~isempty(ix)
    [sortedP,ord]=sort(R.pPrincipal(ix));m=numel(sortedP);
    q=sortedP.*m./(1:m)';
    q=flipud(cummin(flipud(q)));q=min(1,q);
    R.q_BH(ix(ord))=q;
end
writetable(D,fullfile(out,'01_descriptivos_por_grupo.xlsx'));
writetable(R,fullfile(out,'02_comparaciones_A_vs_B.xlsx'));
% sensibilidad: quitar sujetos con menos de 80% de senal valida, SIN borrarlos
sens=base(~base.calidad_baja,:);
S=table('Size',[0 5],'VariableTypes',{'string','double','double','double','double'}, ...
 'VariableNames',{'Variable','nA_calidad','nB_calidad','Media_A','Media_B'});
for k=1:numel(variables)
 x=sens.(variables(k))(sens.grupo=="A");y=sens.(variables(k))(sens.grupo=="B");
 x=x(isfinite(x));y=y(isfinite(y));
 S=[S;{nombres(k),numel(x),numel(y),mean(x),mean(y)}]; %#ok<AGROW>
end
writetable(S,fullfile(out,'03_sensibilidad_calidad.xlsx'));
fid=fopen(fullfile(out,'LEEME_resultados.txt'),'w');
fprintf(fid,'PUNTO 1: comparacion grupos A y B\n');
fprintf(fid,'Tiempo y velocidad estimados mediante EOG, NO cronometrados. Texto: 521 palabras.\n');
fprintf(fid,'Se excluyen seis registros por mala adquisicion, EOG36 pendiente.\n');
fprintf(fid,'Prueba principal Welch (pPrincipal), sensibilidad Mann-Whitney, q BH para 7 variables.\n');
fprintf(fid,'Hedges g >0 significa media A mayor que B. No interpretar causalidad.\n');
fprintf(fid,'Calidad baja (<80%%) es criterio exploratorio, no exclusion automatica.\n');
fprintf(fid,'Revision manual de duraciones de sacadas muy cortas y tiempos estimados recomendada.\n');
fprintf(fid,'Toolbox disponible: %d\n',hayStats);fclose(fid);
fprintf('\nLISTO: abre la carpeta Resultados_Punto1_EOG junto a tu Excel.\n');

function q = prctile_local(x,p)
% interpolacion lineal, no requiere toolbox adicional
 x=sort(x(:)); n=numel(x);
 if n==0,q=NaN;return;end
 pos=1+(n-1)*p/100; lo=floor(pos); hi=ceil(pos);
 q=x(lo)+(pos-lo)*(x(hi)-x(lo));
end
