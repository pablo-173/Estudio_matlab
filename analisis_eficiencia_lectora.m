%% EFICIENCIA LECTORA INTEGRAL - ESTUDIO EOG
% Resultado exploratorio incorporado despues de la revision metodologica.
% Requiere MATLAB R2019b+; usa funciones de MATLAB base (sin toolbox estadistico).
% Abrir el Excel Base_EOG_punto1_actualizada.xlsx, hoja Participantes.
clear; clc; close all;
[file,path] = uigetfile({'*.xlsx;*.csv','Excel o CSV (*.xlsx, *.csv)'}, ...
    'Selecciona la base EOG de participantes');
if isequal(file,0), disp('Se cancelo el analisis.'); return; end
source = fullfile(path,file);
[~,~,ext] = fileparts(file);
if strcmpi(ext,'.csv')
    T = readtable(source,'TextType','string');
else
    T = readtable(source,'Sheet','Participantes','TextType','string');
end
out = fullfile(path,'Resultados_Eficiencia_Lectora');
if ~exist(out,'dir'), mkdir(out); end
requeridas = {'ID','grupo','estado_analisis','puntaje_15','duracion_lectura_s','pct_valido','edad'};
missing = setdiff(requeridas,T.Properties.VariableNames);
if ~isempty(missing), error('Faltan columnas: %s',strjoin(missing,', ')); end
T.ID = upper(strtrim(string(T.ID)));
T.grupo = upper(strtrim(string(T.grupo)));
T.estado_analisis = upper(strtrim(string(T.estado_analisis)));
for var = ["puntaje_15","duracion_lectura_s","pct_valido","edad"]
    if ~isnumeric(T.(var)), T.(var) = str2double(string(T.(var))); end
end
excluidos=["EOG18","EOG19","EOG21","EOG26","EOG30","EOG32"];
T.estado_analisis(ismember(T.ID,excluidos))="EXCLUIDO";
T.estado_analisis(T.ID=="EOG36")="PENDIENTE";
% 521 palabras: misma lectura para todos. Tiempo EOG NO cronometrado.
T.velocidad_estimada_ppm=nan(height(T),1);
tval = isfinite(T.duracion_lectura_s) & T.duracion_lectura_s>0 & T.duracion_lectura_s<1000;
T.velocidad_estimada_ppm(tval)=521*60./T.duracion_lectura_s(tval);
T.comprension_proporcion=nan(height(T),1);
scoreOk=isfinite(T.puntaje_15) & T.puntaje_15>=0 & T.puntaje_15<=15;
T.comprension_proporcion(scoreOk)=T.puntaje_15(scoreOk)/15;
T.eficiencia_integral_ppm=T.velocidad_estimada_ppm.*T.comprension_proporcion;
T.calidad_alta=isfinite(T.pct_valido)&T.pct_valido>=80;
T.usar=ismember(T.grupo,["A","B"]) & T.estado_analisis=="INCLUIDO" ...
  & isfinite(T.eficiencia_integral_ppm);
% Siempre conserva auditoria completa, inclusive excluidos.
writetable(T,fullfile(out,'00_auditoria_calculo_eficiencia.csv'));
base=T(T.usar,:);
if isempty(base), error('No hay participantes elegibles con eficiencia calculable.'); end
writetable(base,fullfile(out,'01_base_eficiencia_A_B.csv'));
fprintf('Registros: %d | usados A=%d, B=%d | excluidos=%d | pendientes=%d\n', ...
    height(T),sum(base.grupo=="A"),sum(base.grupo=="B"), ...
    sum(T.estado_analisis=="EXCLUIDO"),sum(T.estado_analisis=="PENDIENTE"));
% Comparacion principal exploratoria: diferencia de medias Welch (B-A).
R=table('Size',[0 15], 'VariableTypes', ...
    {'string','double','double','double','double','double','double','double', ...
     'double','double','double','double','double','double','string'}, ...
    'VariableNames',{'Muestra','nA','nB','MediaA','MediaB','DEA','DEB', ...
    'MedianaA','MedianaB','Diferencia_BmenosA','IC95_inferior','IC95_superior', ...
    't_Welch','gl_Welch','Interpretacion'});
P=table('Size',[0 3],'VariableTypes',{'string','double','double'}, ...
    'VariableNames',{'Muestra','p_Welch','Hedges_g_BmenosA'});
selecciones={true(height(base),1),base.calidad_alta};
nombres=["Todos_incluidos","Sensibilidad_calidad_80"];
for i=1:2
    S=base(selecciones{i},:);
    a=S.eficiencia_integral_ppm(S.grupo=="A");
    b=S.eficiencia_integral_ppm(S.grupo=="B");
    [dif,ci,t,df,p,g]=welch_custom(a,b);
    if isfinite(p) && p<0.05, interpret="Diferencia nominal p<0.05 (exploratoria)";
    else, interpret="Sin evidencia suficiente de diferencia"; end
    R=[R;{nombres(i),numel(a),numel(b),mean(a),mean(b),std(a),std(b), ...
        median(a),median(b),dif,ci(1),ci(2),t,df,interpret}]; %#ok<AGROW>
    P=[P;{nombres(i),p,g}]; %#ok<AGROW>
end
writetable([R P(:,2:end)],fullfile(out,'02_comparacion_eficiencia.xlsx'));
% Ajuste exploratorio por edad: OLS eficiencia ~ intercepto + grupo(B) + edad
Ajuste=table('Size',[0 8], 'VariableTypes', ...
    {'string','double','double','double','double','double','double','string'}, ...
    'VariableNames',{'Muestra','n','Beta_grupo_BmenosA','EE_beta', ...
      'IC95_inferior','IC95_superior','p_grupo','Estado'});
for i=1:2
    S=base(selecciones{i},:);
    ok=isfinite(S.edad)&isfinite(S.eficiencia_integral_ppm);
    S=S(ok,:);
    if height(S)<6 || numel(unique(S.grupo))<2 || numel(unique(S.edad))<2
        Ajuste=[Ajuste;{nombres(i),height(S),NaN,NaN,NaN,NaN,NaN, ...
            "No estimable: muestra o variacion insuficiente"}]; continue
    end
    X=[ones(height(S),1),double(S.grupo=="B"),S.edad];
    y=S.eficiencia_integral_ppm;
    if rank(X)<3
        Ajuste=[Ajuste;{nombres(i),height(S),NaN,NaN,NaN,NaN,NaN, ...
            "No estimable: colinealidad"}]; continue
    end
    beta=X\y; df=height(S)-3;
    sigma2=sum((y-X*beta).^2)/df;
    covB=sigma2*inv(X'*X); %#ok<MINV>
    se=sqrt(covB(2,2)); crit=student_inv(.975,df);
    p=2*(1-student_cdf(abs(beta(2)/se),df));
    Ajuste=[Ajuste;{nombres(i),height(S),beta(2),se, ...
        beta(2)-crit*se,beta(2)+crit*se,p,"OLS exploratorio, ajustar solo edad"}];
end
writetable(Ajuste,fullfile(out,'03_ajuste_por_edad.xlsx'));
% Figura con puntos individuales, medias y CI 95 % en ambos grupos.
f=figure('Color','w','Position',[200 150 850 540],'Visible','off'); hold on
for k=1:2
    gg=char('A'+k-1); v=base.eficiencia_integral_ppm(base.grupo==string(gg));
    x=k+linspace(-0.11,0.11,numel(v))';
    if k==1, col=[0.12 0.40 0.72]; else, col=[0.85 0.33 0.17]; end
    scatter(x,v,40,col,'filled','MarkerFaceAlpha',0.8);
    mu=mean(v);ci=student_inv(.975,numel(v)-1)*std(v)/sqrt(numel(v));
    plot([k-.18 k+.18],[mu mu],'-','Color',[0 0 0],'LineWidth',2);
    plot([k k],[mu-ci mu+ci],'-k','LineWidth',2);
end
xlim([0.5 2.5]); xticks([1 2]); xticklabels({'Grupo A - Inicial','Grupo B - Avanzado'});
ylabel('Indice de eficiencia (ppm ponderadas por comprension)');
title('Eficiencia lectora integral: 521 palabras y comprension /15');
grid on; set(gca,'FontSize',11); 
text(0.55,max(base.eficiencia_integral_ppm)*.95, ...
    sprintf('Welch p = %.4f (exploratorio)',P.p_Welch(1)),'FontSize',10);
exportgraphics(f,fullfile(out,'04_eficiencia_por_grupo.png'),'Resolution',200); close(f);
% Relacion con la edad como diagnostico descriptivo.
f=figure('Color','w','Position',[200 150 850 500],'Visible','off');hold on
for k=1:2
  gg=char('A'+k-1); idx=base.grupo==string(gg)&isfinite(base.edad);
  if k==1,col=[0.12 .40 .72];else,col=[.85 .33 .17];end
  scatter(base.edad(idx),base.eficiencia_integral_ppm(idx),50,col,'filled');
end
xlabel('Edad (anos)');ylabel('Indice de eficiencia');
legend({'Grupo A','Grupo B'},'Location','best'); grid on;
title('Eficiencia lectora y edad (exploratorio)');
exportgraphics(f,fullfile(out,'05_eficiencia_y_edad.png'),'Resolution',200);close(f);
fid=fopen(fullfile(out,'LEEME_RESULTADOS.txt'),'w');
fprintf(fid,['Indice = (521*60 / duracion_lectura_EOG_s) * (puntaje_15 / 15).\n', ...
'Es una definicion operativa post hoc y exploratoria, NO una medida validada.\n', ...
'La duracion EOG no es un cronometraje independiente y requiere verificar inicio-fin de lectura.\n', ...
'Grupo B vs A; unidad independiente: persona. No incluir controles.\n', ...
'6 EOG excluidos por adquisicion incorrecta; EOG36 pendiente.\n', ...
'Sensibilidad: conservar solo pct_valido >=80. No se descartan permanentemente.\n', ...
'Welch compara medias; OLS compara grupos ajustando por edad, bajo supuestos lineales.\n', ...
'Las inferencias son exploratorias por definicion tardia del indice.\n', ...
'No se ajusto por habitos, carrera, idioma, correccion visual o familiaridad si no se midieron.\n']);
fclose(fid);
fprintf('\nAnalisis completado. Archivos en: %s\n',out);
disp([R P(:,2:end)]);disp(Ajuste);

%% Funciones auxiliares: distribucion t sin Statistics Toolbox
function [delta,ci,t,df,p,g]=welch_custom(a,b)
 a=a(isfinite(a));b=b(isfinite(b));
 delta=NaN;ci=[NaN NaN];t=NaN;df=NaN;p=NaN;g=NaN;
 if numel(a)<3 || numel(b)<3,return;end
 nA=numel(a);nB=numel(b);
 delta=mean(b)-mean(a);vA=var(a);vB=var(b);
 se2=vA/nA+vB/nB;
 if se2<=0,return;end
 t=delta/sqrt(se2);
 df=se2^2/((vA/nA)^2/(nA-1)+(vB/nB)^2/(nB-1));
 p=min(1,2*(1-student_cdf(abs(t),df)));
 ci=delta+[-1 1]*student_inv(.975,df)*sqrt(se2);
 pooled=sqrt(((nA-1)*vA+(nB-1)*vB)/(nA+nB-2));
 if pooled>0,g=(delta/pooled)*(1-3/(4*(nA+nB)-9));end
end
function p=student_cdf(t,df)
 if t==0,p=.5;return;end
 tail=.5*betainc(df/(df+t*t),df/2,.5);
 if t>0,p=1-tail;else,p=tail;end
end
function t=student_inv(q,df)
 if q==.5,t=0;return;end
 sg=sign(q-.5);
 % betaincinv is part of MATLAB base; maps two-tailed t probability to t.
 z=betaincinv(2*min(q,1-q),df/2,.5);
 t=sg*sqrt(df*(1/z-1));
end
