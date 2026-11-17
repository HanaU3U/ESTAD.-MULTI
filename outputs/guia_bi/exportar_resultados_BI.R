# Segundo corte: ejecuta bloques de los DOS Rmd actuales en entornos separados.
# Sin factorial. No modifica fuentes, no teje HTML ni instala paquetes.
# Ejecutar: source(".../outputs/guia_bi/exportar_resultados_BI.R", encoding="UTF-8")
# Otro equipo: definir antes options(bi.raiz="C:/ruta/ESTAD.-MULTI").
# Los resultados se validan en temporal antes de reemplazar SOLO sus archivos
# en DATASET/BI_segundo_corte. No elimina otros archivos de esa carpeta.

exportar_segundo_corte <- function(raiz = getOption("bi.raiz",
  "C:/Users/Ana_L/OneDrive/Documentos/GitHub/ESTAD.-MULTI")) {
  raiz <- normalizePath(raiz, winslash="/", mustWork=TRUE)
  salida <- file.path(raiz,"DATASET","BI_segundo_corte")
  rutas <- c(perfil=file.path(raiz,"Entregables","Segundo Corte","Perfilamiento_Multivariado.Rmd"),
    correspondencias=file.path(raiz,"Ejercicios","analisis_correspondencias_credito.Rmd"),
    csv=file.path(raiz,"DATASET","datos_credit.csv"), xls=file.path(raiz,"DATASET","credit.xls"))
  if (!all(file.exists(rutas))) stop("Faltan fuentes: ",paste(rutas[!file.exists(rutas)],collapse=", "))
  hashes <- tools::md5sum(rutas)
  paquetes <- c("ggplot2","dplyr","tidyr","knitr","readxl","ggrepel","FactoMineR","factoextra")
  faltan <- paquetes[!vapply(paquetes,requireNamespace,logical(1),quietly=TRUE)]
  if (length(faltan)) stop("Instale primero: ",paste(faltan,collapse=", "))
  opciones <- options(); cwd <- getwd(); locale <- Sys.getlocale("LC_CTYPE")
  opts_knitr <- knitr::opts_chunk$get(); tema <- ggplot2::theme_get(); rng <- RNGkind()
  tenia_seed <- exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)
  seed_previa <- if (tenia_seed) get(".Random.seed",envir=.GlobalEnv) else NULL
  tmp <- tempfile("BI_segundo_corte_"); dir.create(tmp)
  grDevices::pdf(file.path(tmp,"graficos_descartados.pdf")); dispositivo <- grDevices::dev.cur()
  on.exit({
    if (dispositivo %in% grDevices::dev.list()) grDevices::dev.off(dispositivo)
    setwd(cwd); options(opciones); knitr::opts_chunk$restore(opts_knitr); ggplot2::theme_set(tema)
    suppressWarnings(Sys.setlocale("LC_CTYPE",locale)); do.call(RNGkind,as.list(rng))
    if (tenia_seed) assign(".Random.seed",seed_previa,envir=.GlobalEnv) else
      if (exists(".Random.seed",envir=.GlobalEnv,inherits=FALSE)) rm(".Random.seed",envir=.GlobalEnv)
    if (!identical(unname(hashes),unname(tools::md5sum(rutas))))
      warning("Alguna fuente cambio durante la ejecucion. Revise modificaciones concurrentes.")
  },add=TRUE)
  options(digits=17,scipen=999)
  controles <- list(); avisos <- character(); ejecutados <- list()
  publicado <- FALSE
  on.exit({
    if (!publicado) {
      if (length(controles)) try(write.csv(do.call(rbind,controles),
        file.path(tmp,"validaciones_interrumpidas.csv"),row.names=FALSE,fileEncoding="UTF-8"),silent=TRUE)
      message("Exportacion NO completada. No use archivos de una ejecucion anterior como resultados nuevos.",
              "\nDiagnostico temporal: ",tmp)
    }
  },add=TRUE)
  verificar <- function(condicion,nombre,detalle="") {
    ok <- isTRUE(condicion)
    controles[[length(controles)+1L]] <<- data.frame(control=nombre,
      resultado=if(ok) "OK" else "ERROR",detalle=detalle)
    if (!ok) stop("Validacion fallida [",nombre,"]: ",detalle,call.=FALSE)
    invisible(TRUE)
  }
  iguales <- function(a,b,tol=1e-8) isTRUE(all.equal(as.vector(a),as.vector(b),
    tolerance=tol,check.attributes=FALSE))
  unica <- function(d,cols,nombre) verificar(!anyNA(d[cols]) && !anyDuplicated(d[cols]),nombre)
  proporcion <- function(x,nombre,na=FALSE) verificar((na || !anyNA(x)) &&
    all(is.finite(x[!is.na(x)])) && all(x[!is.na(x)]>=-1e-8 & x[!is.na(x)]<=1+1e-8),nombre)

  # Extrae bloques por etiqueta, sin cambiar el codigo fuente. Un contrato roto
  # detiene la exportacion en vez de sustituir el analisis por otra version.
  extraer <- function(ruta) {
    out <- list(); abierto <- FALSE; etiqueta <- NULL; codigo <- character()
    for (linea in readLines(ruta,encoding="UTF-8",warn=FALSE)) {
      if (!abierto && grepl("^\\s*```\\{r(?:[ ,}]|$)",linea,perl=TRUE)) {
        h <- sub("^\\s*```\\{r\\s*","",linea,perl=TRUE)
        etiqueta <- trimws(strsplit(h,"[,}]")[[1]][1])
        if (!nzchar(etiqueta) || etiqueta %in% names(out)) stop("Etiqueta ausente/duplicada: ",ruta)
        abierto <- TRUE; codigo <- character()
      } else if (abierto && grepl("^\\s*```\\s*$",linea)) {
        out[[etiqueta]] <- paste(codigo,collapse="\n"); abierto <- FALSE
      } else if (abierto) codigo <- c(codigo,linea)
    }
    if (abierto) stop("Bloque sin cerrar: ",ruta)
    out
  }
  ejecutar <- function(ruta,etiquetas,directorio,capturar=FALSE) {
    bloques <- extraer(ruta)
    verificar(all(etiquetas %in% names(bloques)),"Bloques requeridos",
      paste(setdiff(etiquetas,names(bloques)),collapse=", "))
    e <- new.env(parent=.GlobalEnv); e$.selecciones_bi <- list()
    anterior <- getwd(); setwd(directorio); on.exit(setwd(anterior),add=TRUE)
    for (etiqueta in etiquetas) {
      message(basename(ruta)," :: ",etiqueta)
      for (expr in parse(text=bloques[[etiqueta]],keep.source=TRUE)) {
        withCallingHandlers(eval(expr,envir=e),warning=function(w) {
          avisos <<- c(avisos,paste(basename(ruta),etiqueta,conditionMessage(w),sep=" | "))
          invokeRestart("muffleWarning")
        })
        # Guarda exactamente la mascara que usa evaluar(), incluido el sorteo.
        if (capturar && etiqueta=="validacion" && is.call(expr) &&
            identical(expr[[1]],as.name("<-")) && identical(expr[[2]],as.name("evaluar"))) {
          e$evaluar <- local({
            original <- e$evaluar; entorno <- e
            function(revisar,nombre) {
              entorno$.selecciones_bi[[length(entorno$.selecciones_bi)+1L]] <-
                list(regla=nombre,seleccionado=revisar)
              original(revisar,nombre)
            }
          })
        }
      }
      ejecutados[[length(ejecutados)+1L]] <<- data.frame(documento=basename(ruta),bloque=etiqueta)
    }
    e
  }

  # Identidad completa CSV/Excel, luego ID canonico del Excel.
  raw_csv <- read.csv(rutas[["csv"]],check.names=FALSE,stringsAsFactors=FALSE)
  raw_xls <- as.data.frame(readxl::read_excel(rutas[["xls"]],skip=1))
  canonizar <- function(d) {
    names(d)[grepl("^default",names(d),ignore.case=TRUE)] <- "impago"
    d$EDUCATION[d$EDUCATION %in% c(0,5,6)] <- 4
    d$MARRIAGE[d$MARRIAGE==0] <- 3
    d
  }
  a <- canonizar(raw_csv); b <- canonizar(raw_xls)
  unica(b,"ID","ID Excel unico")
  verificar(nrow(a)==nrow(b),"Poblacion CSV/Excel")
  id_posicional <- !"ID" %in% names(a)
  if (id_posicional) a$ID <- seq_len(nrow(a)) else unica(a,"ID","ID CSV unico")
  pos <- if (id_posicional) seq_len(nrow(a)) else match(a$ID,b$ID)
  verificar(!anyNA(pos),"Correspondencia ID entre fuentes")
  variables <- c("LIMIT_BAL","SEX","EDUCATION","MARRIAGE","AGE","PAY_0",paste0("PAY_",2:6),
    paste0("BILL_AMT",1:6),paste0("PAY_AMT",1:6),"impago")
  verificar(all(variables %in% names(a)) && all(variables %in% names(b)),"Columnas fuente")
  for (v in variables) verificar(iguales(a[[v]],b[[v]][pos],0),paste("Identidad CSV/Excel",v),
    "EDUCATION y MARRIAGE comparadas despues de recodificar; los demas valores deben coincidir.")
  ids_canonicos <- b$ID[pos]
  P <- ejecutar(rutas[["perfil"]],c("setup","lectura","depuracion","resumen-continuas",
    "euclid-vs-maha","transformacion","qq","pca-numerico","reparto-numerico","pca-mixto-config",
    "pca","mapa","atipicos","zonas","reincorporar","validacion","curva-captura"),
    file.path(raiz,"Entregables"),TRUE)
  C <- ejecutar(rutas[["correspondencias"]],c("setup","carga","recodificacion","chi",
    "ca-simple","mca","inercia-mca"),file.path(raiz,"Ejercicios"))
  d <- P$datos; cats <- C$datos
  verificar(nrow(d)==nrow(cats) && nrow(cats)==nrow(b),"Misma poblacion analitica",
    "Si algun Rmd excluye filas, armonizar poblaciones; no se filtran silenciosamente.")
  verificar(!anyNA(cats),"Categorias sin faltantes")
  ix <- match(d$ID,a$ID); verificar(!anyNA(ix),"ID perfil recuperable")
  ID <- ids_canonicos[ix]
  for (v in variables) verificar(iguales(d[[v]],a[[v]][ix],0),paste("Perfil conserva fuente",v))
  verificar(iguales(C$credit$ID,raw_xls$ID,0),"Orden correspondencias")
  verificar(iguales(P$impago_obs,d$impago,0) && all(d$impago %in% 0:1),"Respuesta alineada y binaria")
  verificar(all(is.finite(as.matrix(d[P$continuas]))),"Continuas finitas")
  verificar(P$p==14L,"Mahalanobis de 14 variables")
  tablas <- list(); finalidad <- character()
  agregar <- function(nombre,t,descripcion) {
    t <- as.data.frame(t,stringsAsFactors=FALSE); rownames(t) <- NULL
    verificar(!anyDuplicated(names(t)),paste("Columnas unicas",nombre))
    for (v in names(t)) {
      if (is.factor(t[[v]])) t[[v]] <- as.character(t[[v]])
      if (is.logical(t[[v]])) t[[v]] <- as.integer(t[[v]])
      if (is.numeric(t[[v]])) verificar(!any(is.infinite(t[[v]]) | is.nan(t[[v]])),paste("Sin Inf/NaN",nombre,v))
    }
    tablas[[nombre]] <<- t; finalidad[[nombre]] <<- descripcion
  }

  unica(d,"ID","Perfil unico"); unica(P$mapa,"ID","Mapa unico")
  im <- match(d$ID,P$mapa$ID); verificar(!anyNA(im),"Union mapa completa")
  clientes <- d; clientes$ID_origen_perfil <- clientes$ID; clientes$ID <- ID
  clientes$modelo_id <- "PCA_MIXTO_GLOBAL"
  clientes$Cf <- P$mapa$Cf[im]; clientes$Ca <- P$mapa$Ca[im]
  clientes$D2_original <- P$d2_crudo; clientes$D2_transformada <- P$d2_log
  clientes$distancia_euclidiana_original <- P$euclid
  clientes$atipico_mahalanobis <- as.integer(d$atipico)
  clientes$en_muestra_visual <- as.integer(seq_len(nrow(d)) %in% P$muestra)
  clientes$particion <- ifelse(seq_len(nrow(d)) %in% P$ent,"Entrenamiento","Prueba")
  clientes$zona_orden <- match(as.character(d$zona),P$orden_zonas)
  clientes$d2 <- NULL; clientes$atipico <- NULL; clientes$cliente <- NULL
  unica(clientes,"ID","ID canonico en clientes unico")
  for (k in seq_len(ncol(P$pca$x))) clientes[[paste0("PCA_C",k)]] <- P$pca$x[,k]
  for (k in seq_len(P$k80)) clientes[[paste0("decil_C",k)]] <- dplyr::ntile(P$pca$x[,k],10)
  verificar(iguales(clientes$Cf,P$pca$x[,P$k_fact]) && iguales(clientes$Ca,P$pca$x[,P$k_atr]),"Mapa y componentes")
  verificar(iguales(as.integer(d$atipico),as.integer(P$d2_log>P$corte_99),0),"Corte Mahalanobis")
  zona <- ifelse(clientes$Cf>sd(clientes$Cf) & clientes$Ca>sd(clientes$Ca),P$orden_zonas[1],
    ifelse(clientes$Ca>sd(clientes$Ca),P$orden_zonas[2],
    ifelse(clientes$Cf>sd(clientes$Cf),P$orden_zonas[3],P$orden_zonas[4])))
  verificar(identical(as.character(d$zona),zona),"Zonas y cortes")
  verificar(sum(table(d$zona))==nrow(d) && !anyNA(d$zona),"Total de zonas")
  verificar(all(is.na(d$cobertura_pago[d$BILL_AMT2<=0])),"Cobertura no aplicable NA")
  sel <- d$BILL_AMT2>0
  verificar(iguales(d$cobertura_pago[sel],d$PAY_AMT1[sel]/d$BILL_AMT2[sel]),"Cobertura definida")
  agregar("01_clientes_perfilados.csv",clientes,"Una fila por cliente; puntajes GLOBALES, zonas, distancias, respuesta y particion.")
  verificar(identical(names(cats),c("Educacion","EstadoCivil","Sexo","Edad","Limite","EstadoPago","Incumplimiento")),
    "Contrato categorias","Actualizar diccionario si cambian las columnas del Rmd.")
  categorias <- data.frame(ID=C$credit$ID,cats,check.names=FALSE)
  names(categorias)[-1] <- c("educacion_acm","estado_civil_acm","sexo_acm","grupo_edad_acm",
    "grupo_limite_acm","estado_pago_acm","incumplimiento_etiqueta")
  categorias$PAY_0_original <- C$credit$PAY_0
  categorias$orden_estado_pago <- as.integer(cats$EstadoPago)
  categorias$orden_grupo_limite <- as.integer(cats$Limite); categorias$orden_grupo_edad <- as.integer(cats$Edad)
  unica(categorias,"ID","Categorias ID unico"); verificar(setequal(ID,categorias$ID),"Mismos ID analiticos")
  ci <- match(ID,categorias$ID)
  verificar(iguales(d$impago,as.integer(cats$Incumplimiento[ci]=="Incumple"),0),"Impago entre documentos")
  agregar("02_clientes_categorias.csv",categorias,"Combinar con 01 por ID; no anexar. Categorias exactas de correspondencias.")

  modelos <- list(PCA_NUM14_GLOBAL=P$pca_num,PCA_MIXTO_GLOBAL=P$pca)
  ejes <- cargas <- list()
  for (id in names(modelos)) {
    m <- modelos[[id]]; ev <- m$sdev^2; prop <- ev/sum(ev); k <- seq_along(ev)
    verificar(abs(sum(prop)-1)<1e-10 && abs(sum(ev)-nrow(m$rotation))<1e-8,paste("Varianza PCA",id))
    verificar(!any(grepl("impago|default|^ID$",rownames(m$rotation),ignore.case=TRUE)),paste("Sin respuesta ni ID",id))
    ejes[[id]] <- data.frame(modelo_id=id,componente=k,autovalor=ev,proporcion_varianza=prop,
      proporcion_acumulada=cumsum(prop),es_eje_facturacion=as.integer(id=="PCA_MIXTO_GLOBAL" & k==P$k_fact),
      es_eje_atraso=as.integer(id=="PCA_MIXTO_GLOBAL" & k==P$k_atr))
    cargas[[id]] <- do.call(rbind,lapply(k,function(j) data.frame(modelo_id=id,variable=rownames(m$rotation),
      componente=j,peso=m$rotation[,j],correlacion=m$rotation[,j]*m$sdev[j],contribucion=m$rotation[,j]^2,
      cos2=(m$rotation[,j]*m$sdev[j])^2,media_referencia=as.numeric(m$center),desviacion_referencia=as.numeric(m$scale))))
    verificar(all(abs(colSums(m$rotation^2)-1)<1e-8),paste("Contribuciones PCA",id))
  }
  agregar("03_pca_componentes.csv",do.call(rbind,ejes),"Una componente por modelo; mapa mixto usa k_fact y k_atr.")
  agregar("04_pca_variables.csv",do.call(rbind,cargas),"Pesos orientados; correlaciones reales sin multiplicador visual de flechas.")
  qq <- P$qq; qq$orden <- ave(seq_len(nrow(qq)),qq$escala,FUN=seq_along)
  qq$referencia <- qq$teorica; qq$grados_libertad <- P$p; qq$corte_D2_99 <- P$corte_99
  for (escala in unique(qq$escala)) {
    q <- qq[qq$escala==escala,]
    verificar(nrow(q)==nrow(d) && all(diff(q$observada)>=0),paste("QQ ordenado",escala))
    verificar(iguales(q$teorica,qchisq(ppoints(nrow(d)),P$p)),paste("QQ teorico",escala))
  }
  agregar("05_mahalanobis_qq.csv",qq,"Orden es rango, NO ID. D2 sin log10; referencia Y=X.")

  dic_cat <- do.call(rbind,lapply(names(cats),function(v) do.call(rbind,lapply(levels(cats[[v]]),function(l) {
    s <- cats[[v]]==l
    data.frame(variable=v,categoria=l,categoria_id=paste(v,l,sep="::"),n_categoria=sum(s),
      n_incumplimientos=sum(cats$Incumplimiento[s]=="Incumple"),orden=match(l,levels(cats[[v]])))
  }))))
  verificar(!anyDuplicated(dic_cat$categoria),"Etiquetas FactoMineR no ambiguas",
    "Si hay etiquetas repetidas entre variables, prefijarlas en el Rmd; no adivinar su variable.")
  puntos <- function(obj,modelo,rol,tipo,variable_fija=NULL) {
    labs <- rownames(obj$coord)
    z <- if(is.null(variable_fija)) match(labs,dic_cat$categoria) else
      match(paste(variable_fija,labs,sep="::"),dic_cat$categoria_id)
    verificar(!anyNA(z),paste("Mapeo categorias",modelo,tipo)); info <- dic_cat[z,]
    col <- function(m,k) if(!is.null(m) && ncol(m)>=k) as.numeric(m[,k]) else rep(NA_real_,length(labs))
    out <- data.frame(modelo_id=modelo,punto_id=paste(modelo,tipo,info$categoria_id,sep="|"),
      categoria_id=info$categoria_id,variable=info$variable,categoria=info$categoria,rol=rol,tipo_punto=tipo,
      dim1=col(obj$coord,1),dim2=col(obj$coord,2),cos2_dim1=col(obj$cos2,1),cos2_dim2=col(obj$cos2,2),
      cos2_plano=rowSums(obj$cos2[,seq_len(min(2,ncol(obj$cos2))),drop=FALSE]),
      contrib_dim1=if(rol=="Activo") col(obj$contrib,1)/100 else NA_real_,
      contrib_dim2=if(rol=="Activo") col(obj$contrib,2)/100 else NA_real_,
      n_categoria=info$n_categoria,n_incumplimientos=info$n_incumplimientos,
      tasa_incumplimiento=info$n_incumplimientos/info$n_categoria,orden=info$orden)
    verificar(all(info$n_categoria>0),paste("Frecuencias",modelo,tipo))
    proporcion(out$cos2_plano,paste("Cos2",modelo,tipo)); proporcion(out$tasa_incumplimiento,paste("Tasas",modelo,tipo))
    if(rol=="Activo") verificar(all(abs(colSums(obj$contrib)/100-1)<1e-7),paste("Contribuciones",modelo,tipo)) else
      verificar(all(is.na(out$contrib_dim1)),paste("Suplementarias sin contribucion",modelo,tipo))
    out
  }
  acs_p <- rbind(puntos(C$ca_res$row,"ACS_LIMITE_PAGO","Activo","Fila","Limite"),
    puntos(C$ca_res$col,"ACS_LIMITE_PAGO","Activo","Columna","EstadoPago"),
    puntos(C$ca_res$col.sup,"ACS_LIMITE_PAGO","Suplementario","Columna suplementaria","Incumplimiento"))
  agregar("06_acs_puntos.csv",acs_p,"Limite/estado activos; incumplimiento suplementario. Contribuciones por nube activa.")
  cel <- as.data.frame(C$tab,responseName="observados"); names(cel)[1:2] <- c("limite_categoria","estado_pago_categoria")
  cel$modelo_id <- "ACS_LIMITE_PAGO"; cel$esperados <- as.vector(C$prueba$expected)
  cel$residuo_pearson <- as.vector(C$prueba$residuals); cel$residuo_ajustado <- as.vector(C$prueba$stdres)
  cel$proporcion_dentro_limite <- as.vector(prop.table(C$tab,1))
  cel$proporcion_dentro_estado_pago <- as.vector(prop.table(C$tab,2))
  cel$razon_observado_esperado <- cel$observados/cel$esperados
  verificar(sum(cel$observados)==nrow(cats),"Conteos ACS sin suplementarias")
  verificar(all(cel$esperados>0) && abs(sum(cel$esperados)-nrow(cats))<1e-7,"Esperados ACS")
  agregar("07_acs_celdas.csv",cel,"Solo tabla activa. No sumar tabla_ca: suplementarias duplicarian conteos.")
  eig <- C$ca_res$eig; verificar(abs(sum(eig[,2])/100-1)<1e-7,"Inercia ACS")
  verificar(iguales(sum(eig[,1]),unname(C$prueba$statistic)/sum(C$tab)),
    "ACS inercia corresponde solo a tabla activa")
  agregar("08_acs_ejes.csv",data.frame(modelo_id="ACS_LIMITE_PAGO",dimension=seq_len(nrow(eig)),
    autovalor=eig[,1],proporcion_inercia=eig[,2]/100,proporcion_acumulada=eig[,3]/100),"Inercia de tabla activa.")
  acm_p <- rbind(puntos(C$mca_res$var,"ACM_PERFILES","Activo","Categoria activa"),
    puntos(C$mca_res$quali.sup,"ACM_PERFILES","Suplementario","Categoria suplementaria"))
  verificar(all(acm_p$variable[acm_p$rol=="Suplementario"]=="Incumplimiento") &&
    !any(acm_p$variable[acm_p$rol=="Activo"]=="Incumplimiento"),"Respuesta ACM solo suplementaria")
  agregar("09_acm_categorias.csv",acm_p,"Categorias, no personas. Frecuencias se superponen entre variables.")
  # Algunas versiones de FactoMineR devuelven eig truncado a ncp (5 por
  # defecto). No exigir 100% ni renormalizar esos cinco porcentajes.
  # Ampliar SOLO las dimensiones solicitadas del MISMO modelo; las coordenadas,
  # contribuciones y cos2 de 09/11/18 siguen siendo los originales del Rmd.
  lam_rmd <- C$lambda
  verificar(iguales(lam_rmd,C$mca_res$eig[,1]),"Autovalores ACM propios")
  verificar(iguales(C$lambda_ajust,ifelse(lam_rmd>1/C$Q,
    (C$Q/(C$Q-1)*(lam_rmd-1/C$Q))^2,0)),"Formula inercia ajustada Rmd")
  activas_acm <- setdiff(names(cats),"Incumplimiento")
  K_acm <- sum(vapply(cats[activas_acm],function(x) nlevels(droplevels(x)),integer(1)))
  dimensiones_acm <- min(nrow(cats)-1L,K_acm-C$Q)
  inercia_total_acm <- (K_acm-C$Q)/C$Q
  eig_rmd <- C$mca_res$eig
  espectro_ampliado <- nrow(eig_rmd)<dimensiones_acm
  if (espectro_ampliado) {
    message("ACM: completando espectro de ",nrow(eig_rmd)," a ",dimensiones_acm," dimensiones del mismo modelo.")
    acm_completo <- withCallingHandlers(FactoMineR::MCA(cats,
      quali.sup=which(names(cats)=="Incumplimiento"),ncp=dimensiones_acm,graph=FALSE),
      warning=function(w) {
        avisos <<- c(avisos,paste("ACM espectro completo",conditionMessage(w),sep=" | "))
        invokeRestart("muffleWarning")
      })
    eig_acm <- acm_completo$eig
  } else eig_acm <- eig_rmd
  verificar(nrow(eig_acm)==dimensiones_acm,"Espectro ACM completo",
    paste("Esperadas:",dimensiones_acm,"; recibidas:",nrow(eig_acm)))
  verificar(iguales(eig_acm[seq_len(nrow(eig_rmd)),1],lam_rmd),"Ampliacion conserva autovalores Rmd")
  verificar(iguales(eig_acm[seq_len(nrow(eig_rmd)),2],eig_rmd[,2]),"Ampliacion conserva porcentajes brutos Rmd")
  lam <- eig_acm[,1]
  verificar(iguales(sum(lam),inercia_total_acm),"Inercia ACM teorica (K-Q)/Q")
  verificar(iguales(eig_acm[,2]/100,lam/inercia_total_acm),"Porcentajes ACM con denominador completo")
  verificar(iguales(eig_acm[,3]/100,cumsum(eig_acm[,2]/100)),"Acumulado bruto ACM")
  ajust <- ifelse(lam>1/C$Q,(C$Q/(C$Q-1)*(lam-1/C$Q))^2,0)
  pa <- if(sum(ajust)>0) ajust/sum(ajust) else rep(NA_real_,length(ajust))
  verificar(abs(sum(eig_acm[,2])/100-1)<1e-7,"Suma inercia bruta ACM",
    paste("Suma =",format(sum(eig_acm[,2]),digits=17),
          "; suma autovalores =",format(sum(lam),digits=17)))
  if(sum(ajust)>0) verificar(abs(sum(pa)-1)<1e-10,"Suma inercia ajustada ACM")
  pa_rmd <- if(sum(C$lambda_ajust)>0) C$lambda_ajust/sum(C$lambda_ajust) else rep(NA_real_,length(lam_rmd))
  if (espectro_ampliado) avisos <- c(avisos,paste0(
    "El Rmd devuelve ",length(lam_rmd)," dimensiones ACM; se exportan ",length(lam),
    ". Inercia ajustada del plano: Rmd=",format(sum(pa_rmd[1:2]),digits=10),
    "; espectro completo=",format(sum(pa[1:2]),digits=10),
    ". Usar proporcion_ajustada para el BI; proporcion_ajustada_Rmd es trazabilidad."))
  agregar("10_acm_ejes.csv",data.frame(modelo_id="ACM_PERFILES",dimension=seq_along(lam),autovalor_bruto=lam,
    proporcion_bruta=eig_acm[,2]/100,acumulada_bruta=eig_acm[,3]/100,
    autovalor_ajustado=ajust,proporcion_ajustada=pa,acumulada_ajustada=cumsum(pa),variables_activas=C$Q,
    disponible_en_Rmd=as.integer(seq_along(lam)<=length(lam_rmd)),
    proporcion_ajustada_Rmd=c(pa_rmd,rep(NA_real_,length(lam)-length(lam_rmd)))),
    "Espectro completo del mismo ACM; ajustada usa todos los autovalores. Columna ajustada_Rmd solo para trazabilidad.")
  eta <- C$mca_res$var$eta2
  verificar(setequal(rownames(eta),setdiff(names(cats),"Incumplimiento")),"Variables activas ACM")
  eta_l <- do.call(rbind,lapply(seq_len(ncol(eta)),function(k) data.frame(
    modelo_id="ACM_PERFILES",variable=rownames(eta),dimension=k,eta2=eta[,k])))
  proporcion(eta_l$eta2,"Eta2 en 0-1")
  agregar("11_acm_variables.csv",eta_l,"Relacion variable-dimension; eta2 no es contribucion y no suma 100%.")

  verificar(length(intersect(P$ent,P$prueba))==0 && setequal(c(P$ent,P$prueba),seq_len(nrow(d))),"Particion disjunta completa")
  verificar(length(P$.selecciones_bi)==nrow(P$reglas),"Todas las reglas capturadas")
  verificar(sum(P$y)>0 && sum(P$y)<length(P$y),"Prueba contiene ambas respuestas")
  nombres_reglas <- c("20 % más alto en el eje de atraso","20 % más alto en el eje de facturación",
    "Zona de atraso (eje de atraso > 1 DE)","Atraso en septiembre (PAY_0 ≥ 1)","Atípico de Mahalanobis","Al azar (20 %)")
  verificar(identical(as.character(P$reglas$regla),nombres_reglas),"Contrato reglas validacion")
  detalle <- list()
  for(j in seq_along(P$.selecciones_bi)) {
    s <- P$.selecciones_bi[[j]]; mask <- s$seleccionado
    verificar(is.logical(mask) && length(mask)==length(P$y) && !anyNA(mask),paste("Mascara",s$regla))
    verificar(any(mask) && any(!mask),paste("Ambos grupos en regla",s$regla))
    r <- P$reglas[j,]; verificar(identical(s$regla,as.character(r$regla)),"Orden reglas")
    esperado <- c(mean(mask),mean(P$y[mask]),mean(P$y[!mask]),sum(P$y[mask])/sum(P$y))
    registrado <- unlist(r[c("revisados_pct","tasa_impago_revisados","tasa_impago_no_revisados","impagos_capturados_pct")])/100
    verificar(iguales(esperado,registrado),paste("Metricas vs seleccion",s$regla))
    verificar(iguales(mean(P$y[mask])/mean(P$y),r$veces_la_tasa_global),paste("Lift",s$regla))
    detalle[[j]] <- data.frame(evaluacion_id="HOLDOUT_2026_70_30",ID=ID[P$prueba],regla_id=paste0("R",j),
      regla=s$regla,seleccionado=as.integer(mask),impago=P$y)
  }
  val <- P$reglas; val$evaluacion_id <- "HOLDOUT_2026_70_30"; val$regla_id <- paste0("R",seq_len(nrow(val)))
  val$n_entrenamiento <- length(P$ent); val$n_prueba <- length(P$prueba)
  val$n_impagos_prueba <- sum(P$y); val$tasa_global_prueba <- mean(P$y)
  val$n_revisados <- vapply(P$.selecciones_bi,function(s) sum(s$seleccionado),numeric(1))
  val$n_impagos_capturados <- vapply(P$.selecciones_bi,function(s) sum(P$y[s$seleccionado]),numeric(1))
  val$proporcion_revisados <- val$revisados_pct/100; val$revisados_pct <- NULL
  val$tasa_impago_revisados <- val$tasa_impago_revisados/100; val$tasa_impago_no_revisados <- val$tasa_impago_no_revisados/100
  val$proporcion_impagos_capturados <- val$impagos_capturados_pct/100; val$impagos_capturados_pct <- NULL
  val$umbral <- c(quantile(P$sc_ent[,P$ka],.8),quantile(P$sc_ent[,P$kf],.8),sd(P$sc_ent[,P$ka]),1,P$corte_99,.2)
  val$operador <- c(">=",">=",">",">=",">","runif <")
  val$origen_umbral <- c(rep("Entrenamiento",3),"Regla fija","Chi-cuadrado 14 gl","Bernoulli p=0.2; semilla 7")
  agregar("12_validacion_reglas.csv",val,"Metricas en prueba. Percentil 80 de entrenamiento no implica 20% exacto en prueba.")
  cur <- P$curvas; cur$evaluacion_id <- "HOLDOUT_2026_70_30"
  cur$orden <- ave(seq_len(nrow(cur)),cur$regla,FUN=seq_along)
  cur$proporcion_revisados <- cur$revisados_pct/100; cur$revisados_pct <- NULL
  cur$proporcion_impagos_capturados <- cur$capturados_pct/100; cur$capturados_pct <- NULL
  for(reg in unique(cur$regla)) {
    g <- cur[cur$regla==reg,]
    verificar(nrow(g)==length(P$y) && all(diff(g$proporcion_impagos_capturados)>=-1e-12) &&
      abs(tail(g$proporcion_impagos_capturados,1)-1)<1e-10 && abs(tail(g$proporcion_revisados,1)-1)<1e-10,paste("Curva captura",reg))
  }
  agregar("13_validacion_curvas.csv",cur,"Ranking de prueba, distinto de seleccion por umbral de entrenamiento.")

  meta <- list()
  met <- function(modelo,parametro,valor) {
    meta[[length(meta)+1L]] <<- data.frame(modelo_id=modelo,parametro=parametro,
      valor=if(is.numeric(valor)) format(valor,digits=17,scientific=FALSE,trim=TRUE) else as.character(valor),
      tipo=if(is.numeric(valor)) "numero" else "texto")
  }
  met("GENERAL","fecha_exportacion",format(Sys.time(),tz="America/Bogota",usetz=TRUE))
  met("GENERAL","ID","ID original credit.xls; identidad CSV verificada por todos los valores")
  met("GENERAL","CSV_ID_posicional",as.character(id_posicional)); met("GENERAL","n",nrow(d))
  met("GENERAL","incumplimientos",sum(d$impago)); met("GENERAL","moneda","NT$ (nuevo dolar taiwanes)")
  met("GENERAL","periodo","Abril-septiembre 2005; resultado mes siguiente")
  for(id in names(modelos)) {
    m <- modelos[[id]]; pr <- m$sdev^2/sum(m$sdev^2)
    met(id,"n",nrow(m$x)); met(id,"columnas",nrow(m$rotation)); met(id,"componentes_superar_80",which(cumsum(pr)>.8)[1])
    met(id,"escala","Originales; centrado y Z-score; sin logaritmos")
  }
  met("PCA_MIXTO_GLOBAL","eje_facturacion",P$k_fact); met("PCA_MIXTO_GLOBAL","eje_atraso",P$k_atr)
  met("PCA_MIXTO_GLOBAL","varianza_plano",sum(P$pct[c(P$k_fact,P$k_atr)])/100)
  met("PCA_MIXTO_GLOBAL","corte_facturacion",sd(P$mapa$Cf)); met("PCA_MIXTO_GLOBAL","corte_atraso",sd(P$mapa$Ca))
  met("PCA_MIXTO_GLOBAL","n_muestra_visual",length(P$muestra)); met("PCA_MIXTO_GLOBAL","semilla_muestra",19)
  met("PCA_MIXTO_GLOBAL","zoom_x_min",P$lim_x[1]); met("PCA_MIXTO_GLOBAL","zoom_x_max",P$lim_x[2])
  met("PCA_MIXTO_GLOBAL","zoom_y_min",P$lim_y[1]); met("PCA_MIXTO_GLOBAL","zoom_y_max",P$lim_y[2])
  met("PCA_MIXTO_GLOBAL","multiplicador_visual_flechas",P$esc)
  met("MAHALANOBIS_GLOBAL","corte_D2_99",P$corte_99); met("MAHALANOBIS_GLOBAL","gl",P$p)
  met("MAHALANOBIS_GLOBAL","transformacion","log(cupo); slog(facturas); log1p(pagos); edad original")
  met("MAHALANOBIS_GLOBAL","interpretacion","Corte orientativo, no probabilidad de impago ni certeza de error")
  met("ACS_LIMITE_PAGO","chi2",unname(C$prueba$statistic)); met("ACS_LIMITE_PAGO","gl",unname(C$prueba$parameter))
  met("ACS_LIMITE_PAGO","p_valor",C$prueba$p.value); met("ACS_LIMITE_PAGO","V_Cramer",C$v_cramer)
  met("ACS_LIMITE_PAGO","esperado_minimo",min(C$prueba$expected))
  met("ACS_LIMITE_PAGO","celdas_esperado_menor5",sum(C$prueba$expected<5))
  met("ACS_LIMITE_PAGO","suplementarias","Incumplimiento proyectado por su distribucion entre grupos de limite")
  met("ACM_PERFILES","variables_activas",C$Q)
  met("ACM_PERFILES","dimensiones_devueltas_Rmd",length(lam_rmd))
  met("ACM_PERFILES","dimensiones_espectro_completo",length(lam))
  met("ACM_PERFILES","inercia_total_teorica",inercia_total_acm)
  met("ACM_PERFILES","plano_ajustado_Rmd",sum(pa_rmd[1:2]))
  met("ACM_PERFILES","plano_ajustado_completo",sum(pa[1:2]))
  met("ACM_PERFILES","ajuste_inercia","Benzecri: [Q/(Q-1)*(lambda-1/Q)]^2 si lambda>1/Q; normalizacion por suma ajustada")
  met("HOLDOUT_2026_70_30","semilla_particion",2026); met("HOLDOUT_2026_70_30","semilla_azar",7)
  met("HOLDOUT_2026_70_30","eje_facturacion",P$kf); met("HOLDOUT_2026_70_30","eje_atraso",P$ka)
  met("HOLDOUT_2026_70_30","tipo","Particion interna aleatoria; no validacion temporal ni externa")
  agregar("14_metadatos_modelos.csv",do.call(rbind,meta),"Formato largo parametro-valor; columna tipo para su interpretacion.")
  lim <- as.numeric(quantile(C$credit$LIMIT_BAL,probs=0:4/4)); verificar(all(diff(lim)>0),"Cortes limite unicos")
  verificar(identical(as.character(cats$Limite),as.character(cut(C$credit$LIMIT_BAL,lim,
    include.lowest=TRUE,labels=levels(cats$Limite)))),"Reproduccion cuartiles")
  agregar("15_limites_categorias.csv",data.frame(variable="LIMIT_BAL",categoria=levels(cats$Limite),
    limite_inferior=head(lim,-1),limite_superior=tail(lim,-1),incluye_inferior=c(1L,0L,0L,0L),
    incluye_superior=1L,orden=1:4,unidad="NT$"),"Cortes fijos; intervalos cerrados a derecha, primero tambien a izquierda.")
  det <- do.call(rbind,detalle); unica(det,c("evaluacion_id","ID","regla_id"),"Detalle validacion unico")
  agregar("16_validacion_clientes_reglas.csv",det,"Una fila por cliente de prueba y regla. Usar ID distintos entre reglas.")
  agregar("17_validacion_puntajes.csv",data.frame(evaluacion_id="HOLDOUT_2026_70_30",ID=ID[P$prueba],impago=P$y,
    Cf_prueba=P$sc_pru[,P$kf],Ca_prueba=P$sc_pru[,P$ka],D2_prueba=P$d2_pru,orden_original_prueba=seq_along(P$prueba)),
    "Solo prueba, con modelos de entrenamiento. No reemplazar puntajes globales de 01.")
  verificar(nrow(C$mca_res$ind$coord)==nrow(cats),"Individuos ACM alineados")
  agregar("18_acm_individuos.csv",data.frame(modelo_id="ACM_PERFILES",ID=C$credit$ID,
    dim1=C$mca_res$ind$coord[,1],dim2=C$mca_res$ind$coord[,2],cos2_plano=rowSums(C$mca_res$ind$cos2[,1:2,drop=FALSE])),
    "Coordenadas de personas; separadas de categorias.")
  dic_cat$tasa_incumplimiento <- dic_cat$n_incumplimientos/dic_cat$n_categoria
  for(v in unique(dic_cat$variable)) {
    g <- dic_cat[dic_cat$variable==v,]
    verificar(sum(g$n_categoria)==nrow(cats) && sum(g$n_incumplimientos)==sum(d$impago),paste("Totales categorias",v))
  }
  agregar("19_categorias_tasas_globales.csv",dic_cat,"Control global sin redondeo; no sumar frecuencias entre variables.")
  cz <- dplyr::summarise(dplyr::group_by(clientes,zona),clientes=dplyr::n(),incumplimientos=sum(impago),
    atipicos=sum(atipico_mahalanobis),.groups="drop")
  verificar(sum(cz$incumplimientos)==sum(d$impago),"Impagos por zonas")
  agregar("20_zonas_control.csv",cz,"Reconciliacion global; calcular filtros desde 01.")
  claves <- list(
    "03_pca_componentes.csv"=c("modelo_id","componente"),
    "04_pca_variables.csv"=c("modelo_id","variable","componente"),
    "05_mahalanobis_qq.csv"=c("escala","orden"),
    "06_acs_puntos.csv"="punto_id",
    "07_acs_celdas.csv"=c("modelo_id","limite_categoria","estado_pago_categoria"),
    "08_acs_ejes.csv"=c("modelo_id","dimension"),
    "09_acm_categorias.csv"="punto_id",
    "10_acm_ejes.csv"=c("modelo_id","dimension"),
    "11_acm_variables.csv"=c("modelo_id","variable","dimension"),
    "12_validacion_reglas.csv"=c("evaluacion_id","regla_id"),
    "13_validacion_curvas.csv"=c("evaluacion_id","regla","orden"),
    "14_metadatos_modelos.csv"=c("modelo_id","parametro"),
    "17_validacion_puntajes.csv"=c("evaluacion_id","ID"),
    "18_acm_individuos.csv"=c("modelo_id","ID"),
    "19_categorias_tasas_globales.csv"="categoria_id")
  for (nom in names(claves)) unica(tablas[[nom]],claves[[nom]],paste("Clave exportada",nom))
  for(nom in names(tablas)) {
    t <- tablas[[nom]]
    for(v in grep("^proporcion|^acumulada|^tasa_|^cos2|^contrib",names(t),value=TRUE))
      proporcion(t[[v]],paste("Proporcion",nom,v),na=TRUE)
  }
  verificar(identical(unname(hashes),unname(tools::md5sum(rutas))),"Fuentes intactas antes de exportar")
  agregar("91_fuentes.csv",data.frame(fuente=names(rutas),ruta=unname(rutas),md5=unname(hashes)),"Huellas de cuatro fuentes.")
  agregar("92_bloques_ejecutados.csv",do.call(rbind,ejecutados),"Bloques exactos; sin factorial ni analisis alternativo.")
  agregar("93_advertencias_R.csv",data.frame(advertencia=unique(avisos)),"Advertencias de los modelos; revisar antes de usar resultados.")

  # Comprobacion de serializacion: UTF-8, columnas, NA y precision numerica.
  escribir <- function(t,nombre) write.table(t,file.path(tmp,nombre),sep=",",dec=".",row.names=FALSE,
    col.names=TRUE,quote=TRUE,na="",fileEncoding="UTF-8",qmethod="double")
  for(nom in names(tablas)) {
    t <- tablas[[nom]]; escribir(t,nom)
    tipos <- vapply(t,function(x) if(is.integer(x)) "integer" else if(is.numeric(x)) "numeric" else "character",character(1))
    rt <- read.csv(file.path(tmp,nom),check.names=FALSE,colClasses=tipos,na.strings="",fileEncoding="UTF-8",stringsAsFactors=FALSE)
    verificar(identical(dim(rt),dim(t)) && identical(names(rt),names(t)),paste("Relectura esquema",nom))
    for(v in names(t)) {
      if(is.numeric(t[[v]])) verificar(iguales(t[[v]],rt[[v]],1e-12),paste("Relectura numerica",nom,v)) else
        verificar(identical(as.character(t[[v]]),as.character(rt[[v]])),paste("Relectura texto",nom,v))
    }
  }
  verificar(identical(unname(hashes),unname(tools::md5sum(rutas))),"Fuentes intactas tras comprobaciones")
  tablas[["90_validaciones.csv"]] <- do.call(rbind,controles)
  finalidad[["90_validaciones.csv"]] <- "Controles previos a publicacion. Todos deben indicar OK."
  escribir(tablas[["90_validaciones.csv"]],"90_validaciones.csv")
  dic <- do.call(rbind,lapply(names(tablas),function(nom) {
    t <- tablas[[nom]]
    data.frame(archivo=nom,columna=names(t),tipo=vapply(t,function(x) class(x)[1],character(1)),
      vacios=vapply(t,function(x) sum(is.na(x)),integer(1)),descripcion_tabla=finalidad[[nom]])
  }))
  escribir(dic,"94_diccionario_columnas.csv")
  writeLines(c("BI SEGUNDO CORTE - SIN FACTORIAL",
    "01 y 02: combinar por ID, nunca anexar. 03-11: modelos globales, no se recalculan al filtrar clientes.",
    "12-13 y 16-17: prueba 30%, ajuste 70%; no mezclar con puntajes globales de 01.",
    "16 repite personas entre reglas: contar ID distintos. 05 orden no es ID, valores son D2.",
    "06/09 suplementarias sin contribucion. No sumar las columnas suplementarias del ACS al contar personas.",
    "10 contiene espectro completo: usar proporcion_ajustada; proporcion_ajustada_Rmd conserva el calculo original posiblemente truncado.",
    "Ampliar ncp completa autovalores sin modificar el modelo ni los mapas de 09/18. 19 repite personas entre variables.",
    "Conservar NA de cobertura cuando BILL_AMT2<=0. Uso/cobertura pueden superar 1; no recortar.",
    "Etiquetas -2 Sin consumo, -1 Pago total y 0 Credito rotativo se preservan del Rmd; confirmar semantica.",
    "UTF-8, coma separadora, punto decimal. Proporciones 0-1, sin redondear para presentacion.",
    "90 contiene controles, 93 advertencias R y 94 tipos/vacios. Revisar antes de cargar el BI.",
    "99_manifest.csv se publica al final; comprobar sus MD5 si se interrumpe una copia.",
    "Rareza no equivale a incumplimiento; validacion interna no justifica aprobacion automatica de credito."),
    file.path(tmp,"LEEME_BI.txt"),useBytes=TRUE)
  capture.output(sessionInfo(),file=file.path(tmp,"versiones_paquetes.txt"))
  publicar <- c(names(tablas),"94_diccionario_columnas.csv","LEEME_BI.txt","versiones_paquetes.txt")
  manifest <- data.frame(archivo=publicar,
    filas=vapply(publicar,function(nom) if(nom %in% names(tablas)) nrow(tablas[[nom]]) else NA_integer_,integer(1)),
    md5=unname(tools::md5sum(file.path(tmp,publicar))))
  escribir(manifest,"99_manifest.csv")
  dir.create(salida,recursive=TRUE,showWarnings=FALSE)
  for(nom in publicar) {
    if(!file.copy(file.path(tmp,nom),file.path(salida,nom),overwrite=TRUE))
      stop("No se pudo copiar ",nom,"; cierre aplicaciones que lo bloqueen. Temporal: ",tmp)
    verificar(identical(unname(tools::md5sum(file.path(tmp,nom))),unname(tools::md5sum(file.path(salida,nom)))),paste("Copia final",nom))
  }
  if(!file.copy(file.path(tmp,"99_manifest.csv"),file.path(salida,"99_manifest.csv"),overwrite=TRUE))
    stop("Fallo el manifiesto final. Resultados temporales: ",tmp)
  publicado <- TRUE
  message("Exportacion completa: ",normalizePath(salida,winslash="/"),"\n",length(tablas)+2L,
    " CSV; ",nrow(clientes)," clientes; ",sum(d$impago)," incumplimientos. Revise 90, 93 y LEEME_BI.txt.")
  invisible(list(carpeta=salida,manifest=manifest))
}

exportar_segundo_corte()
