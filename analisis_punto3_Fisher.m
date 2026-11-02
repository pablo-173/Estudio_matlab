%% FISIOLOGIA - PUNTO 3: COMPARACION DE CORRELACIONES A vs B (FISHER)
% 4 relaciones: velocidad vs duracion mediana de fijaciones, duracion
% mediana de sacadas, tasa de sacadas y comprension lectora.
% NO requiere toolboxes adicionales: usa funciones base de MATLAB.
% Entrada: Base_EOG_punto1_actualizada.xlsx, hoja Participantes.
% Una observacion por participante; controles fuera de A vs B.
% Fisher compara CORRELACIONES DE PEARSON entre muestras independientes.
% Las correlaciones Spearman NO se comparan directamente con esta prueba.
clear; clc; close all;

[archivo, ruta] = uigetfile({'*.xlsx;*.csv','Excel o CSV (*.xlsx,*.csv)'}, ...
    'Selecciona la base de participantes EOG');
if isequal(archivo,0), disp('Operacion cancelada.'); return; end
entrada = fullfile(ruta,archivo);
[~,~,extension] = fileparts(entrada);
if strcmpi(extension,'.csv')
    T=readtable(entrada,'TextType','string','VariableNamingRule','preserve');
else
    T=readtable(entrada,'Sheet','Participantes', ...
        'TextType','string','VariableNamingRule','preserve');
end

requeridas = ["ID","grupo","estado_analisis","duracion_lectura_s", ...
    "puntaje_15","mediana_fijaciones_ms","mediana_sacadas_ms", ...
    "tasa_sacadas_min","pct_valido"];
faltan = requeridas(~ismember(requeridas,string(T.Properties.VariableNames)));
if ~isempty(faltan)
    error('Faltan columnas: %s',char(strjoin(faltan,', ')));
end
numericas = ["duracion_lectura_s","puntaje_15", ...
    "mediana_fijaciones_ms","mediana_sacadas_ms", ...
    "tasa_sacadas_min","pct_valido"];
for k=1:numel(numericas)
    nom=char(numericas(k));
    if ~isnumeric(T.(nom))
        T.(nom)=str2double(strrep(string(T.(nom)),',','.'));
    end
end
T.ID=upper(regexprep(strtrim(string(T.ID)),'\s+',''));
T.grupo=upper(strtrim(string(T.grupo)));
T.estado_analisis=upper(strtrim(string(T.estado_analisis)));
% Exclusiones confirmadas por el equipo de investigacion.
excluidos=["EOG18","EOG19","EOG21","EOG26","EOG30","EOG32"];
T.estado_analisis(ismember(T.ID,excluidos))="EXCLUIDO";
T.estado_analisis(T.ID=="EOG36")="PENDIENTE";

% Todos leyeron 521 palabras. Tiempo EOG: estimacion, no cronometro.
T.velocidad_ppm=NaN(height(T),1);
buenTiempo=isfinite(T.duracion_lectura_s) & ...
    T.duracion_lectura_s>0 & T.duracion_lectura_s<1000;
T.velocidad_ppm(buenTiempo)=521*60./T.duracion_lectura_s(buenTiempo);
T.comprension_pct=100*T.puntaje_15/15;
T.calidad_baja=isfinite(T.pct_valido)&T.pct_valido<80;
B=T(T.estado_analisis=="INCLUIDO" & ismember(T.grupo,["A","B"]),:);

out=fullfile(ruta,'Resultados_Punto3_Fisher');
if ~exist(out,'dir'),mkdir(out);end
writetable(B,fullfile(out,'00_participantes_A_B.csv'));

vars=["mediana_fijaciones_ms","mediana_sacadas_ms", ...
    "tasa_sacadas_min","comprension_pct"];
labels=["Velocidad vs duracion mediana de fijaciones", ...
    "Velocidad vs duracion mediana de sacadas", ...
    "Velocidad vs tasa de sacadas", ...
    "Velocidad vs comprension lectora"];

% Analisis principal con todos los registros elegibles.
R=calcularFisher(B,vars,labels);
R.q_BH=ajusteBH(R.p_bilateral);
R.significativo_p05=R.p_bilateral<0.05;
R.significativo_q05=R.q_BH<0.05;
writetable(R,fullfile(out,'01_resultados_Fisher_A_vs_B.xlsx'));

% Sensibilidad: excluye TEMPORALMENTE pct_valido <80; no borra datos.
BS=B(~B.calidad_baja,:);
S=calcularFisher(BS,vars,labels);
S.q_BH=ajusteBH(S.p_bilateral);
writetable(S,fullfile(out,'02_Fisher_sensibilidad_calidad.xlsx'));

% Figura descriptiva de r de Pearson + IC aproximados de cada grupo.
f=figure('Color','w','Position',[80 80 1150 600]); hold on;
colores=[0.10 0.40 0.70; 0.85 0.35 0.20];
for k=1:height(R)
    for g=1:2
        if g==1
            r=R.r_A(k); l=R.IC95_rA_inf(k); u=R.IC95_rA_sup(k);
            ypos=k-0.13;
        else
            r=R.r_B(k); l=R.IC95_rB_inf(k); u=R.IC95_rB_sup(k);
            ypos=k+0.13;
        end
        if all(isfinite([r l u]))
            plot([l,u],[ypos,ypos],'-','LineWidth',2,'Color',colores(g,:));
            plot(r,ypos,'o','MarkerSize',8,'MarkerFaceColor',colores(g,:), ...
                'MarkerEdgeColor',colores(g,:));
        end
    end
end
xline(0,'k--','LineWidth',1);
yticks(1:4);yticklabels(labels);set(gca,'YDir','reverse');
xlim([-1 1]);ylim([0.4,4.6]);grid on;box on;
xlabel('Correlacion de Pearson r e IC 95 % por grupo');
title('Punto 3: correlaciones en grupo A y grupo B');
plot(nan,nan,'o','Color',colores(1,:),'MarkerFaceColor',colores(1,:),'DisplayName','Grupo A');
plot(nan,nan,'o','Color',colores(2,:),'MarkerFaceColor',colores(2,:),'DisplayName','Grupo B');
legend('Location','best');
exportgraphics(f,fullfile(out,'03_comparacion_correlaciones.png'),'Resolution',200);
close(f);

fprintf('\n===== FISHER: DIFERENCIA DE CORRELACIONES DE PEARSON =====\n');
disp(R(:,{'Relacion','n_A','n_B','r_A','r_B','z_Fisher','p_bilateral','q_BH'}));
fprintf('A: %d registros; B: %d registros.\n',sum(B.grupo=="A"),sum(B.grupo=="B"));
fprintf('Archivo principal: %s\n',fullfile(out,'01_resultados_Fisher_A_vs_B.xlsx'));
fprintf(['Interpretacion: p/q >= 0.05 no prueba igualdad; ', ...
    'solo indica que no se detecto diferencia bajo este contraste.\n']);
fprintf(['Precaucion: velocidades estimadas por EOG y correlaciones ', ...
    'sensibles a valores extremos/no linealidad.\n']);

%% FUNCIONES LOCALES
function R=calcularFisher(T,vars,labels)
    R=table('Size',[numel(vars),15], ...
        'VariableTypes',{'string','double','double','double','double', ...
            'double','double','double','double','double','double', ...
            'double','double','double','double'}, ...
        'VariableNames',{'Relacion','n_A','n_B','r_A','r_B', ...
            'IC95_rA_inf','IC95_rA_sup','IC95_rB_inf','IC95_rB_sup', ...
            'z_Fisher','p_bilateral','delta_z','IC95_delta_z_inf', ...
            'IC95_delta_z_sup','SE_delta_z'});
    for k=1:numel(vars)
        R.Relacion(k)=labels(k);
        A=T(T.grupo=="A",:);B=T(T.grupo=="B",:);
        x=A.velocidad_ppm;y=A.(char(vars(k)));
        ok=isfinite(x)&isfinite(y);x=x(ok);y=y(ok);
        a=numel(x); R.n_A(k)=a;
        [ra,ica]=correlacionPearson(x,y);
        x=B.velocidad_ppm;y=B.(char(vars(k)));
        ok=isfinite(x)&isfinite(y);x=x(ok);y=y(ok);
        b=numel(x); R.n_B(k)=b;
        [rb,icb]=correlacionPearson(x,y);
        R.r_A(k)=ra;R.r_B(k)=rb;
        R.IC95_rA_inf(k)=ica(1);R.IC95_rA_sup(k)=ica(2);
        R.IC95_rB_inf(k)=icb(1);R.IC95_rB_sup(k)=icb(2);
        if a>3 && b>3 && isfinite(ra) && isfinite(rb) && ...
                abs(ra)<1 && abs(rb)<1
            delta=atanh(ra)-atanh(rb); % Diferencia en escala z de Fisher
            se=sqrt(1/(a-3)+1/(b-3));
            z=delta/se;
            p=erfc(abs(z)/sqrt(2)); % 2 colas; normal estandar, MATLAB base
            R.delta_z(k)=delta;R.SE_delta_z(k)=se;
            R.z_Fisher(k)=z;R.p_bilateral(k)=p;
            R.IC95_delta_z_inf(k)=delta-1.95996398454*se;
            R.IC95_delta_z_sup(k)=delta+1.95996398454*se;
        else
            R.delta_z(k)=NaN;R.SE_delta_z(k)=NaN;
            R.z_Fisher(k)=NaN;R.p_bilateral(k)=NaN;
            R.IC95_delta_z_inf(k)=NaN;R.IC95_delta_z_sup(k)=NaN;
        end
    end
end

function [r,ci]=correlacionPearson(x,y)
    r=NaN;ci=[NaN NaN];n=numel(x);
    if n<4 || numel(unique(x))<2 || numel(unique(y))<2
        return;
    end
    C=corrcoef(x,y); r=C(1,2);
    if isfinite(r) && abs(r)<1
        se=1/sqrt(n-3);
        ci=tanh(atanh(r)+[-1 1]*1.95996398454*se);
    end
end

function q=ajusteBH(p)
    q=NaN(size(p));idx=find(isfinite(p));
    if isempty(idx),return;end
    [ordenados,orden]=sort(p(idx));m=numel(idx);
    val=ordenados.*m./(1:m)';
    val=min(1,flipud(cummin(flipud(val))));
    q(idx(orden))=val;
end
