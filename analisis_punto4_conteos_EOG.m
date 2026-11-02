%% FISIOLOGIA - PUNTO 4: MODELOS DE CONTEO EOG
% Poisson y binomial negativa NB2 para numero de sacadas y fijaciones.
% Predictor: grupo B vs A. Offset log(tiempo valido EN MINUTOS).
% Usa MATLAB base (fminsearch, gammaln, erfc); NO requiere Statistics Toolbox.
% NOTA: modelos mixtos de duraciones requieren eventos individuales.
% No utilizar el tiempo total del archivo ni el tiempo de lectura como
% exposicion de eventos contados EN LA SENAL LIMPIA.
clear; clc; close all;

[nombre, carpeta]=uigetfile({'*.xlsx;*.csv','Bases (*.xlsx, *.csv)'}, ...
    'Selecciona Base_EOG_punto1_actualizada.xlsx');
if isequal(nombre,0), disp('Cancelado.'); return; end
archivo=fullfile(carpeta,nombre);
[~,~,extension]=fileparts(archivo);
if strcmpi(extension,'.csv')
    T=readtable(archivo,'TextType','string','VariableNamingRule','preserve');
else
    T=readtable(archivo,'Sheet','Participantes','TextType','string', ...
        'VariableNamingRule','preserve');
end
requeridas=["ID","grupo","estado_analisis","num_sacadas", ...
    "num_fijaciones","tiempo_valido_s","pct_valido"];
faltantes=requeridas(~ismember(requeridas,string(T.Properties.VariableNames)));
if ~isempty(faltantes)
    error('Faltan columnas en la base: %s',char(strjoin(faltantes,', ')));
end
for nom=["num_sacadas","num_fijaciones","tiempo_valido_s","pct_valido"]
    n=char(nom);
    if ~isnumeric(T.(n))
        T.(n)=str2double(strrep(string(T.(n)),',','.'));
    end
end
T.ID=upper(regexprep(strtrim(string(T.ID)),'\s+',''));
T.grupo=upper(strtrim(string(T.grupo)));
T.estado_analisis=upper(strtrim(string(T.estado_analisis)));
excluidos=["EOG18","EOG19","EOG21","EOG26","EOG30","EOG32"];
T.estado_analisis(ismember(T.ID,excluidos))="EXCLUIDO";
T.estado_analisis(T.ID=="EOG36")="PENDIENTE";
% Analisis principal: grupos A y B incluidos (no controles).
B=T(T.estado_analisis=="INCLUIDO" & ismember(T.grupo,["A","B"]),:);
if numel(unique(B.ID))~=height(B)
    error('Hay ID duplicados en la base A/B; revisalos antes de analizar.');
end
if height(B)<8 || sum(B.grupo=="A")<4 || sum(B.grupo=="B")<4
    error('No hay participantes suficientes en ambos grupos.');
end
B.exposicion_min=B.tiempo_valido_s/60;
B.tasa_sacadas_recalculada=B.num_sacadas./B.exposicion_min;
B.tasa_fijaciones_recalculada=B.num_fijaciones./B.exposicion_min;
B.calidad_menor80=isfinite(B.pct_valido)&B.pct_valido<80;

salida=fullfile(carpeta,'Resultados_Punto4_Conteos');
if ~exist(salida,'dir'),mkdir(salida);end
writetable(B,fullfile(salida,'00_registros_A_B_auditados.csv'));
variables=["num_sacadas","num_fijaciones"];
titulos=["Sacadas","Fijaciones"];

% Todos los datos con exposicion y conteo validos.
[R,D]=ejecutarModelos(B,variables,titulos,"Principal");
R.q_BH_NB=nan(height(R),1);
idx=R.Modelo=="Binomial negativa NB2";
R.q_BH_NB(idx)=ajusteBH(R.p(idx));
writetable(R,fullfile(salida,'01_resultados_modelos.xlsx'));
writetable(D,fullfile(salida,'02_descriptivos_sacadas_fijaciones.xlsx'));

% Sensibilidad: registros con >=80 %% de tiempo limpio.
BS=B(~B.calidad_menor80,:);
[RS,DS]=ejecutarModelos(BS,variables,titulos,"Calidad >=80%");
writetable(RS,fullfile(salida,'03_modelos_sensibilidad.xlsx'));
writetable(DS,fullfile(salida,'04_descriptivos_sensibilidad.xlsx'));

% Grafica: comparacion de tasas observadas por participante.
f=figure('Color','w','Position',[90 90 1050 490]);
for j=1:2
    subplot(1,2,j); hold on;
    ok=esValido(B.(char(variables(j))),B.exposicion_min);
    for g=1:2
        if g==1, grupo="A"; col=[0.12 0.40 0.68]; else, grupo="B"; col=[0.85 0.35 0.17]; end
        conteos=B.(char(variables(j)));
        sel=ok & B.grupo==grupo;
        v=conteos(sel)./B.exposicion_min(sel);
        if ~isempty(v)
            scatter(g+linspace(-0.08,0.08,numel(v))',v,28,col,'filled');
            plot([g-0.22,g+0.22],[median(v),median(v)],'k-','LineWidth',2);
        end
    end
    xlim([0.5 2.5]);xticks([1 2]);xticklabels({'A - Inicial','B - Avanzado'});
    ylabel('Eventos/minuto de SENAL VALIDA');title(char(titulos(j)));
    grid on;box on;
end
sgtitle('Conteos EOG normalizados por tiempo de senal valida');
exportgraphics(f,fullfile(salida,'05_tasas_observadas.png'),'Resolution',200);
close(f);

% Grafica de razones de tasas con IC95 de los modelos.
f=figure('Color','w','Position',[90 90 860 420]);hold on;
for j=1:2
    for m=1:2
        if m==1, modelo="Poisson"; color=[0.15 0.45 0.75]; d=-0.13;
        else, modelo="Binomial negativa NB2"; color=[0.87 0.38 0.2]; d=0.13; end
        ii=find(R.Variable==titulos(j) & R.Modelo==modelo,1);
        if ~isempty(ii) && all(isfinite([R.RR_B_vs_A(ii),R.IC95_RR_inf(ii),R.IC95_RR_sup(ii)]))
            y=j+d;
            plot([R.IC95_RR_inf(ii),R.IC95_RR_sup(ii)],[y,y],'-','Color',color,'LineWidth',2);
            plot(R.RR_B_vs_A(ii),y,'o','Color',color,'MarkerFaceColor',color,'MarkerSize',8);
        end
    end
end
xline(1,'k--');yticks(1:2);yticklabels(cellstr(titulos));
xlabel('Razon de tasas B/A (IC 95 %)');
title('Poisson vs binomial negativa: efecto de grupo');grid on;box on;
hP=plot(nan,nan,'o','Color',[0.15 0.45 0.75],'MarkerFaceColor',[0.15 0.45 0.75]);
hN=plot(nan,nan,'o','Color',[0.87 0.38 0.2],'MarkerFaceColor',[0.87 0.38 0.2]);
legend([hP,hN],{'Poisson','Binomial negativa NB2'},'Location','best');
exportgraphics(f,fullfile(salida,'06_razones_de_tasas.png'),'Resolution',200);
close(f);

fprintf('\n====== PUNTO 4: MODELOS DE CONTEO ======\n');
disp(R(:,{'Variable','Modelo','n_A','n_B','RR_B_vs_A', ...
    'IC95_RR_inf','IC95_RR_sup','p','Dispersion_Pearson','AIC','Estado'}));
fprintf('Registros elegibles A/B: %d (A=%d, B=%d)\n', ...
    height(B),sum(B.grupo=="A"),sum(B.grupo=="B"));
fprintf('Los seis descartados, EOG36 y controles no participan.\n');
fprintf(['Importante: Poisson supone Var(Y)=E(Y). ', ...
    'Si hay sobredispersion, preferir NB2 cuando converja.\n']);
fprintf(['La inferencia Wald es aproximada y sensible a muestras pequenas. ', ...
    'Verificar resultados y diagnosticos.\n']);
fprintf('Archivos generados en: %s\n',salida);

%% FUNCIONES
function ok=esValido(y,t)
    ok=isfinite(y)&isfinite(t)&t>0&y>=0&abs(y-round(y))<1e-7;
end

function [R,D]=ejecutarModelos(T,variables,titulos,etapa)
    R=table(); D=table();
    for j=1:numel(variables)
        nom=char(variables(j)); y=T.(nom);
        t=T.exposicion_min;
        ok=esValido(y,t);
        U=T(ok,:);y=y(ok);t=t(ok);
        grupo=U.grupo;
        nA=sum(grupo=="A");nB=sum(grupo=="B");
        if nA<4 || nB<4
            warning('%s: insuficientes participantes. Se omite.',nom);
            continue;
        end
        for g=["A","B"]
            b=grupo==g; tasas=y(b)./t(b);
            d=table(etapa,titulos(j),g,sum(b),sum(y(b)),sum(t(b)), ...
                sum(y(b))/sum(t(b)),median(tasas), ...
                'VariableNames',{'Etapa','Variable','Grupo','N','Conteos_totales', ...
                'Minutos_validos','Tasa_agrupada_min','Mediana_tasa_individual'});
            D=[D;d]; %#ok<AGROW>
        end
        X=[ones(numel(y),1),double(grupo=="B")];
        offset=log(t);
        % Poisson: maxima verosimilitud via fminsearch.
        [pfit,pinfo]=modeloPoisson(y,X,offset);
        [nfit,ninfo]=modeloNB(y,X,offset,pfit.beta);
        modelos={pfit,nfit};infos=[pinfo,ninfo];
        for k=1:2
            M=modelos{k}; name=string(M.nombre);
            if isfinite(M.beta(2)) && isfinite(M.se(2)) && M.se(2)>0
                rr=exp(M.beta(2)); l=exp(M.beta(2)-1.96*M.se(2));
                u=exp(M.beta(2)+1.96*M.se(2));p=erfc(abs(M.beta(2)/M.se(2))/sqrt(2));
            else
                rr=NaN;l=NaN;u=NaN;p=NaN;
            end
            fila=table(etapa,titulos(j),name,nA,nB,numel(y), ...
                sum(y),sum(t),rr,l,u,p, M.disp,M.aic,M.alpha, ...
                infos(k),string(M.estado), ...
                'VariableNames',{'Etapa','Variable','Modelo','n_A','n_B','n_total', ...
                'Conteos_totales','Minutos_validos','RR_B_vs_A', ...
                'IC95_RR_inf','IC95_RR_sup','p','Dispersion_Pearson', ...
                'AIC','Alpha_NB2','Exitflag','Estado'});
            R=[R;fila]; %#ok<AGROW>
        end
    end
end
function [M,flag]=modeloPoisson(y,X,off)
    theta0=[log((sum(y)+0.1)/sum(exp(off)));0];
    opts=optimset('Display','off','MaxFunEvals',30000,'MaxIter',30000, ...
        'TolX',1e-9,'TolFun',1e-9);
    [beta,nll,flag]=fminsearch(@(b)nllPoisson(b,y,X,off),theta0,opts);
    mu=exp(min(X*beta+off,700));
    H=X'*(X.*mu);
    cov=invSegura(H);
    diagonal=diag(cov);
    diagonal(diagonal<=0)=NaN;
    se=sqrt(diagonal);
    dispPear=sum((y-mu).^2./max(mu,eps))/max(numel(y)-2,1);
    M=struct('nombre','Poisson','beta',beta,'se',se,'disp',dispPear, ...
        'aic',2*2+2*nll,'alpha',NaN,'estado','OK');
    if flag<=0 || any(~isfinite(se))
        M.estado='REVISAR: convergencia o Hessiana';
        M.se(:)=NaN;
    end
end
function [M,flag]=modeloNB(y,X,off,betaP)
    muP=exp(min(X*betaP+off,700));
    alpha0=max(0.02, min(3,(sum((y-muP).^2-y)/max(sum(muP.^2),eps))));
    ini=[betaP; log(alpha0)];
    opts=optimset('Display','off','MaxFunEvals',50000,'MaxIter',50000, ...
        'TolX',1e-8,'TolFun',1e-8);
    [theta,nll,flag]=fminsearch(@(th)nllNB(th,y,X,off),ini,opts);
    beta=theta(1:2);alpha=exp(theta(3));
    mu=exp(min(X*beta+off,700));
    H=hessianaNumerica(@(th)nllNB(th,y,X,off),theta);
    cov=invSegura(H);
    diagonal=diag(cov);
    diagonal(diagonal<=0)=NaN;
    se=sqrt(diagonal);
    dispPear=sum((y-mu).^2./max(mu+alpha*mu.^2,eps))/max(numel(y)-3,1);
    M=struct('nombre','Binomial negativa NB2','beta',beta, ...
        'se',se(1:2),'disp',dispPear,'aic',2*3+2*nll, ...
        'alpha',alpha,'estado','OK');
    if flag<=0 || any(~isfinite(se)) || alpha<1e-6 || alpha>1e3
        M.estado='REVISAR: convergencia, dispersion o Hessiana';
        M.se(:)=NaN;
    end
end
function v=nllPoisson(b,y,X,off)
    eta=X*b+off;
    if any(~isfinite(eta)) || any(eta>500),v=realmax/1e10;return;end
    mu=exp(eta);
    v=sum(mu-y.*eta+gammaln(y+1));
    if ~isfinite(v),v=realmax/1e10;end
end
function v=nllNB(theta,y,X,off)
    if any(~isfinite(theta)) || abs(theta(3))>20
        v=realmax/1e10;return;
    end
    eta=X*theta(1:2)+off;
    if any(~isfinite(eta)) || any(eta>500),v=realmax/1e10;return;end
    mu=exp(eta);r=exp(-theta(3));
    % NB2: media mu; Var=mu+alpha*mu^2; r=1/alpha.
    logp=gammaln(y+r)-gammaln(r)-gammaln(y+1)+ ...
        r.*(log(r)-log(r+mu))+y.*(log(mu)-log(r+mu));
    v=-sum(logp);
    if ~isfinite(v),v=realmax/1e10;end
end
function H=hessianaNumerica(fun,x)
    n=numel(x);H=zeros(n,n);fx=fun(x);
    h=1e-4*max(1,abs(x));
    for i=1:n
        ei=zeros(n,1);ei(i)=h(i);
        H(i,i)=(fun(x+ei)-2*fx+fun(x-ei))/h(i)^2;
        for j=i+1:n
            ej=zeros(n,1);ej(j)=h(j);
            hij=(fun(x+ei+ej)-fun(x+ei-ej)-fun(x-ei+ej)+fun(x-ei-ej))/(4*h(i)*h(j));
            H(i,j)=hij;H(j,i)=hij;
        end
    end
end
function C=invSegura(H)
    C=NaN(size(H));
    if all(isfinite(H(:))) && rcond(H)>1e-10 && all(eig((H+H')/2)>0)
        C=inv(H);
    end
end
function q=ajusteBH(p)
    q=NaN(size(p));validos=find(isfinite(p));
    if isempty(validos),return;end
    [ps,ind]=sort(p(validos));m=numel(ps);
    qa=flipud(cummin(flipud(ps(:).*m./(1:m)')));
    qa=min(1,qa);q(validos(ind))=qa;
end
