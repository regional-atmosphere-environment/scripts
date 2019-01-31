;=======================================================;
;  combine_qfed_finn_ers.ncl
;=======================================================;
;
; Concepts illustrated:
;   - Load qfed CO2 (or CO) files
;   - Load Christine's emission values
;         (separated into 4 land types)
;   - Calculate emission factors
;   - Multiply CO2 (or CO) by emission factors for each species
;      and change units to molec/cm^2/s
;   - Regrid from 0.25 x 0.25 to 1.9 x2.5
;                          or to 0.94 x 1.25
;   - Regrid lon gridding,
;          -180 to 180 qfed : 0 to 360 CAM-chem
;   - Write out to netCDF - one file per tracer per year
;                         - kept at daily time resolution
;   - changed to use base emission factors for relevant VOCs
;     rather than NMOC x a scaling factor
;   
;   To run type {options in curly braces}:
;         ncl {year=<value>} combine_qfed_finn_ers_new.ncl
;
;   Requires:
;         path to qfed files separated into years
;         path to FINN 4-land type emission ratios file
;         path to FINN 4-land type VOC speciation
;         path to MOZART molecular weight file
;         emission ratio files must have line (or column for VOC) order:
;         1: Savanna Grasslands
;         2: Shrublands/Savanna
;         3: Tropical Forest
;         4: Extratropical Forest
;                                  RRB January 28, 2019
;=======================================================;
; load the libraries
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/contributed.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_code.ncl"
load "$NCARG_ROOT/lib/ncarg/nclscripts/csm/gsn_csm.ncl"

begin

;--------------------------------------------
; user input
;--------------------------------------------
  if (.not. isvar("NRT")) then        ; is NRT=<boolean> from command line?
       NRT = False
  end if

  if (NRT) then
    if (.not. isvar("YYYYMMDD")) then      ; is YYYYMMDD=<value> from command line?
       YYYYMMDD = 20171101
    end if
    splitdate = str_split_by_length(tostring(YYYYMMDD), 4)
    year = toint(splitdate(0))
    year_range = "2018_2020"
    outres = "0.9x1.25"
    ratio_species = "co2"
    species = "CO2"
    outpath = "/net/modeling1/data14b/buchholz/qfed/cam_"+outres+"/from_"+ratio_species+"/nrt/"
    MIN_EF         = False
    MAX_EF         = False
  else
    if (.not. isvar("year")) then      ; is year=<value> from command line?
       year = 2018
    end if
    qfed_version = "v2.5"
    outres = "0.9x1.25"
    ratio_species = "co2"
    species = "CO2"
    outpath = "/net/modeling1/data14b/buchholz/qfed/cam_"+outres+"/from_"+ratio_species+"/"+qfed_version+"/"+year+"/"
    ;------------
    ; toggles
    ;------------
    MIN_EF         = False
    MAX_EF         = False
  end if

  ; -------------------------------
  ; QFED files
  ; -------------------------------

  if (NRT) then
    qfed_dir = "/net/modeling1/data14b/buchholz/qfed/orig_0.25/"+ratio_species+"_nrt/"
    qfed_files = systemfunc ("ls "+qfed_dir+"*"+YYYYMMDD+"*.nc4")
  else
    qfed_dir = "/net/modeling1/data14b/buchholz/qfed/orig_0.25/"+ratio_species+"_"+year+"/"
    qfed_files = systemfunc ("ls "+qfed_dir+"*"+year+"*.nc4")
  end if

  ;------------
  ; toggles
  ;------------
  netCDF         = True                       ; for netCDF output
  PLOT           = False

  ; -------------------------------
  ; FINN emission ratios
  ; -------------------------------
  if (MAX_EF)
    finn_emiss = "/net/modeling1/home/buchholz/data/Base_emissionfactors_speciation_max_jun2017.csv"
    outpath = "/net/modeling1/data14b/buchholz/qfed/cam_"+outres+"/from_"+ratio_species+"/"+qfed_version+"/"+year+"_max/"
  else if (MIN_EF)
    finn_emiss = "/net/modeling1/home/buchholz/data/Base_emissionfactors_speciation_min_jun2017.csv"
    outpath = "/net/modeling1/data14b/buchholz/qfed/cam_"+outres+"/from_"+ratio_species+"/"+qfed_version+"/"+year+"_min/"
  else
    finn_emiss = "/net/modeling1/home/buchholz/data/Base_emissionfactors_speciation_jan2019.csv"
  end if
  end if

  ; -------------------------------
  ; MOZART molecular weights
  ; -------------------------------
  molwts = "/net/modeling1/home/buchholz/data/species_molwts.txt"

;--------------------------------------------
; end user input
;--------------------------------------------

;********************************************
; set up
  ; -------------------------------
  ; names of QFED data structures
  ; determined from an ncl_filedump
  ; -------------------------------
  qfed_co2           = "biomass"
  qfed_co2_trop      = "biomass_tf"
  qfed_co2_extratrop = "biomass_xf"
  qfed_co2_savanna   = "biomass_sv"
  qfed_co2_grass     = "biomass_gl"
  qfed_time          = "time"

  ; -------------------------------
  ; plotting parameters
  ; -------------------------------
  if (PLOT) then
    mapType = "x11"
    mapName = "test"
  end if ;PLOT

  ; -------------------------------
  ; constants
  ; -------------------------------
   NAv = 6.022e23              ; Avogadro's number, molecules mole^-1

   re   = 6.37122e06              ; Earth radius
   rad  = 4.0 * atan(1.0) / 180.0 ; For area sums/avg
   con  = re * rad                 

   ; load molecular weights (g/mol) from a MOZART file,
   ; augmented with additional values for:
   ; CO2, OC and BC copied from OC1 and CB1
   mw_dummy  = asciiread(molwts,-1,"string")
   mw_dummy2 = mw_dummy(2:)
   mol_wts = new((/dimsizes(mw_dummy2),2/), string)
   do s = 0,dimsizes(mw_dummy2)-1
     mol_wts(s,:) = str_split(mw_dummy2(s)," ")
   end do

  ; -------------------------------
  ; lat/lon for re-gridding
  ; -------------------------------

  if (outres.eq."0.9x1.25") then
   ; higher res - 1 deg
   newlon  = fspan(0,358.75, 288)
     newlon@units      = "degrees_east"
     newlon@long_name  = "longitude"
     newlon!0          = "lon"
     newlon&lon        = newlon
   newlat  = fspan(-90,90, 192)
     newlat@units      = "degrees_north"
     newlat@long_name  = "latitude"
     newlat!0          = "lat"
     newlat&lat        = newlat
  else
    ; lower res - 2 deg
   newlon  = fspan(0,357.5, 144)
     newlon@units      = "degrees_east"
     newlon@long_name  = "longitude"
     newlon!0          = "lon"
     newlon&lon        = newlon
   newlat  = fspan(-90,90, 96)
     newlat@units      = "degrees_north"
     newlat@long_name  = "latitude"
     newlat!0          = "lat"
     newlat&lat        = newlat
   end if

  ; -------------------------------
  ; CAM-chem res for sums/avgs
  ; -------------------------------
     clat = cos(newlat * rad)        ; cosine of latitude
     dlon = (newlon(2) - newlon(1))  ; assume dlon is constant
     dlat = (newlat(2) - newlat(1))  ; assume dlat is constant
     dx   = con * dlon * clat        ; dx at each latitude
     dy   = con * dlat               ; dy is constant
     dydx = dy * dx                  ; dydx(nlat)
   
     wgt_CAM  = new((/dimsizes(newlat), dimsizes(newlon)/), float)
     wgt_CAM  = conform(wgt_CAM, dydx, 0)


;********************************************
; load files and extract
 ; -------------------------------
  ; load FINN emission ratios
  ; -------------------------------
  ;---read the values in as 1D lines
  emiss_g  = asciiread(finn_emiss,-1,"string")

  ;--- collect data
  delim  = ","
  header = emiss_g(0)
  data = emiss_g(1:)
  nlines = dimsizes(data)
  ncols  = dimsizes(str_split(data(0),delim))
  print("columns = " + ncols)
  print(header)

  ;--- separate header for species name
  dummy_var = str_split_csv(header,delim,0)
  dummy_var2 = dummy_var(0,1:)
  var_names = str_upper(dummy_var2)
  ;--- replace names to be consistent with MOZART
  var_names = where(var_names.eq."NOX AS NO","ignore",var_names)   ; ignore NOx - use NO and NO2
  var_names = where(var_names.eq."SO2","SO2_orig",var_names)   ; split up SO2

  ;---reshape data to 2D array, and convert to float
  strs = str_split_csv (data, delim, 0)  
  ltype = strs(:,0)                 ;--- land type names
  e_fields = tofloat(strs(:,1:))    ;--- emission values
    ;--- define attributes
    e_fields!0 = "vegtype"
    e_fields&vegtype = ltype
    e_fields!1 = "tracer"
    e_fields&tracer = var_names
    e_fields@units = "g/kg"
    e_fields@_FillValue = -9999.99
    e_fields = where(ismissing(e_fields),0,e_fields) ; replace missing with zeros for calculations

  ; -------------------------------
  ; compute factors
  ; -------------------------------
   e_factors = e_fields
   if (ratio_species.eq."co2") then
     do k=0,nlines-1                                      
       e_factors(k,:) = e_fields(k,:)/e_fields(k,0)
     end do
   else if (ratio_species.eq."co") then
     do k=0,nlines-1                                      
       e_factors(k,:) = e_fields(k,:)/e_fields(k,1)
     end do
   end if
   end if
     e_factors@units = "g/kg per g/kg"

  ; -------------------------------
  ; QFED load
  ; -------------------------------
    fin = addfiles(qfed_files, "r")            ; read in
    ListSetType (fin, "cat") 
      co2_all          = fin[:]->$qfed_co2$
      co2_trop         = fin[:]->$qfed_co2_trop$
      co2_xtrop        = fin[:]->$qfed_co2_extratrop$
      co2_savan        = fin[:]->$qfed_co2_savanna$
      co2_grass        = fin[:]->$qfed_co2_grass$

      ; load and convert time format
      time_dummy       = fin[:]->$qfed_time$
      time = tofloat(cd_convert(time_dummy, "days since 1850-01-01 00:00:00" ))
        time@long_name = "Time"
        time@calendar = "Gregorian"
        time!0 = "time"
        time&time = time
        time@units = "days since 1850-01-01 00:00:00"

      date = cd_calendar(time_dummy,-2)
        date!0 = "time"
        date&time = time
        date@long_name = "Date"
        date@units = "YYYYMMDD"
        delete(date@calendar)

      delete(co2_all&time )
      co2_all!0 = "time"
      co2_all&time = (time)

  ; -------------------------------
  ; QFED res for sums/avgs
  ; -------------------------------
     clat_q = cos(co2_all&lat * rad) ; cosine of latitude
     dlon_q = (co2_all&lon(2) - co2_all&lon(1))  ; assume dlon is constant
     dlat_q = (co2_all&lat(2) - co2_all&lat(1))  ; assume dlat is constant
     dx_q   = con * dlon_q * clat_q   ; dx at each latitude
     dy_q   = con * dlat_q            ; dy is constant
     dydx_q = dy_q * dx_q             ; dydx(nlat)

     wgt_QFED  = new((/dimsizes(co2_all&lat), dimsizes(co2_all&lon)/), float)
     wgt_QFED  = conform(wgt_QFED, tofloat(dydx_q), 0)

  ;********************************************
  ; Non- VOCs
  ;--- FINN                    QFED
  ;                          kg s-1 m-2
  ; Savanna Grasslands       co2_grass
  ; Shrublands/Savanna       co2_savan
  ; Tropical Forest          co2_xtrop
  ; Extratropical Forest     co2_trop

  do tracer = 0,dimsizes(var_names)-1
  ;do tracer = 2,4
    if (var_names(tracer).eq."NMOC".or.\
        var_names(tracer).eq."ignore".or.\
        var_names(tracer).eq."PM2.5".or.\
        var_names(tracer).eq."PM10") then
      continue
    else
      ; -------------------------------
      ; calculate emissions for non-VOCs
      ; -------------------------------
      tracer_emiss:= co2_grass * e_factors(0,tracer) +\
                     co2_savan * e_factors(1,tracer) +\
                     co2_trop * e_factors(2,tracer) +\
                     co2_xtrop * e_factors(3,tracer)
    end if
    copy_VarAtts(co2_all,tracer_emiss)
    copy_VarCoords(co2_all,tracer_emiss)
    ;printVarSummary(tracer_emiss)

    ; -------------------------------
    ; convert to CAM-Chem units
    ; kg s-1 m-2 to molec. cm-2 s-1
    ; -------------------------------
     print(var_names(tracer))
     if (var_names(tracer).eq."SO2_orig")
        mw = tofloat(mol_wts(ind(mol_wts(:,0).eq."SO2"),1))
     else
        mw = tofloat(mol_wts(ind(mol_wts(:,0).eq.var_names(tracer)),1))
     end if
     print(var_names(tracer)+" MW: "+mw)
     tracer_emiss = tracer_emiss/(10000)        ; m-2 -> cm-2
     tracer_emiss = (tracer_emiss*1000/mw)*NAv  ; kg -> g -> mol -> molec
       tracer_emiss@units = "molecules/cm2/s"

    ; -------------------------------
    ; regrid to CAM-chem structure
    ; 1.9 x 2.5 or 0.94 x 1.25
    ; -------------------------------
     opt    = False
     emiss_regrid  := area_conserve_remap_Wrap(tracer_emiss&lon,tracer_emiss&lat, \
                                         tracer_emiss , \
                                         newlon, newlat, opt)  ; (ntim,96,144)
     ;printVarSummary(emiss_regrid)

     ;--- sanity check
     SumOrigGrid = wgt_areasum2 (tracer_emiss , wgt_QFED, 0)
     Sum_Regrid = wgt_areasum2 (emiss_regrid, wgt_CAM, 0)
     SumDiff = SumOrigGrid-Sum_Regrid

   if (any(SumOrigGrid.eq.0)) then
     print("No emissions for "+var_names(tracer)+" in some entries of " + year)
     nonzero_ind = ind(SumOrigGrid.ne.0)
     print("Specifically:")
     zero_ind = ind(SumOrigGrid.eq.0)
     print(date(zero_ind))
     PercDiff = (SumDiff(nonzero_ind)/SumOrigGrid(nonzero_ind))*100
     print("-------------------------------------------------")
     print("lowres: "+SumOrigGrid+", highres: "+Sum_Regrid)
   else
     PercDiff = (SumDiff/SumOrigGrid)*100
   end if

     ;PercDiff = (SumDiff/SumOrigGrid)*100
     MaxDiff = max(PercDiff)
     max_ind := ind(PercDiff.eq.MaxDiff)
   ;print("Maximum diff: lowres: "+sprintf("%2.2e",SumOrigGrid(max_ind))+\
   ;      "  highres: "+sprintf("%2.2e",Sum_Regrid(max_ind))+   \
   ;      "    diff: "+sprintf("%2.2e",SumDiff(max_ind))+  \
   ;      "   percent diff: "+sprintf("%2.2f",PercDiff(max_ind))+"%")

   print("Maximum percent diff in "+var_names(tracer)+\
         " from regridding: "+sprintf("%2.2f",PercDiff(max_ind))+"%"+\
         " on date: " + cd_calendar(co2_all&time(max_ind),2))
   print("-------------------------------------------------")

    ;--------------------------------------------
    ; Write out to an netCDF file
    ;--------------------------------------------
    if (netCDF) then
      ;-------------------
      ; create file for each 
      ; CAM-chem species
      ;-------------------
      if (NRT) then
        outfilename = "qfed.emis_"+var_names(tracer)+"_"+outres+"_mol_"+year_range+".nc"
        template = addfile(outpath+outfilename, "r")            ; read in
           date_template = template->date
           bb_template = template->bb
;printVarSummary(bb_template)
           bb_template = where(ismissing(bb_template),0,bb_template) ; replace missing with zeros for calculations
           bb_template = where(bb_template.eq.1e+20,0,bb_template) ; replace missing with zeros for calculations
           delete(bb_template@_FillValue)
           delete(bb_template@missing_value)
           delete(bb_template@fmissing_value)
           bb_template@_FillValue := 0.0
           bb_template@missing_value := 0.0
           bb_template@fmissing_value := 0.0

;printVarSummary(bb_template)
;exit

        fout = addfile(outpath+outfilename, "w")                ; ready for some overwriting
      else if (MIN_EF)
        outfilename = "qfed.emis.min_"+var_names(tracer)+"_"+outres+"_mol_"+year+".nc"
        fout = addfile(outpath+outfilename, "c")
      else if (MAX_EF)
        outfilename = "qfed.emis.max_"+var_names(tracer)+"_"+outres+"_mol_"+year+".nc"
        fout = addfile(outpath+outfilename, "c")
      else 
        outfilename = "qfed.emis_"+var_names(tracer)+"_"+outres+"_mol_"+year+".nc"
        fout = addfile(outpath+outfilename, "c")
      end if
      end if
      end if

      if (NRT) then
         ind_overwrite = ind(date_template.eq.date)
           delete(emiss_regrid@missing_value)
           delete(emiss_regrid@fmissing_value)
           emiss_regrid = where(ismissing(emiss_regrid),0,emiss_regrid) ; replace missing with zeros for calculations
           emiss_regrid@_FillValue := 0.0
           emiss_regrid@missing_value := 0.0
           emiss_regrid@fmissing_value := 0.0
           emiss_regrid@vmax   := tofloat(max(emiss_regrid))
           emiss_regrid@vmin   := tofloat(min(emiss_regrid))

         emiss_overwrite = bb_template
         ten_forward = ind_overwrite+10
         xnew = rm_single_dims(emiss_regrid)
         emiss_conform = conform(emiss_overwrite(ind_overwrite:ten_forward,:,:),xnew, (/1,2/))
         emiss_overwrite(ind_overwrite:ten_forward,:,:) = (/emiss_conform/)
           emiss_overwrite@vmax   := tofloat(max(emiss_overwrite))
           emiss_overwrite@vmin   := tofloat(min(emiss_overwrite))
           emiss_overwrite@long_name := dummy_var2(tracer)+" QFED/FINN fire emissions"

       ;--- emissions
         fout->bb               = emiss_overwrite

      else
      ;------------
      ; File 
      ; Attributes
      ;------------
      setfileoption(fout, "DefineMode",True)
      fAtt                      = True
        fAtt@molecular_weight   = mw
        fAtt@conventions        = "CF"
        fAtt@history            = species+" is from QFED, Level3b v2.5 "+\
                                  "(qfed-2.5_r1) Gridded Emission Estimates, with "+\
                                  "FINN emission ratios applied"
        fAtt@author             = "R. R. Buchholz (buchholz@ucar.edu)"
        fAtt@creation_date      = systemfunc ("date")
        fAtt@source             = "QFED Level3b v2.5_r1 Gridded Emission Estimates:"+\
                                  " NASA/GSFC/GMAO GEOS-5 Aerosol Group;"+\
                                  " FINN v1.6: C. Wiedinmyer 2015"
        fAtt@title              = "Emissions of "+ var_names(tracer)+\
                                  " from FINN v1.6 x QFED " +\
                                   species+", daily"

       fileattdef(fout, fAtt)
       setfileoption(fout, "DefineMode",False)

      ;------------
      ; Coordinate Variables
      ;------------
        dimNames = (/"time", "lat", "lon"/)  
	dim_Sizes = (/ -1   ,  dimsizes(emiss_regrid&lat),  dimsizes(emiss_regrid&lon)/) 
	dimUnlim = (/ True , False, False/)
	filedimdef(fout,dimNames,dim_Sizes,dimUnlim)
      ;------------
      ; Variables
      ;------------
      emiss_regrid@long_name = dummy_var2(tracer)+" QFED/FINN fire emissions"
      ;emiss_regrid@_FillValue := 0.0
      emiss_regrid@vmax      = max(emiss_regrid)
      emiss_regrid@vmin      = min(emiss_regrid)
      ;delete(emiss_regrid@missing_value)
      ;delete(emiss_regrid@fmissing_value)

       ;--- date
         fout->date             = date
       ;--- emissions
         fout->bb               = emiss_regrid
      end if

    end if ;NetCDF

  tracername := var_names(tracer)

  end do ; g/kg emission factors


  ;********************************************
  ; panel plots for consistency check
  ;-------------------
  ; MAP PLOT
  ;-------------------
  if (PLOT) then
    wks = gsn_open_wks(mapType,mapName)
    gsn_define_colormap(wks,"sunshine_9lev")        ; change colour map
    ;-------------------
    ; define resources 
    ; to use for plotting
    ;-------------------
    mapres = True
    mapres@tiMainString              = ""                  ; changing main large title
    mapres@gsnLeftString             = ""                  ; change left 
    mapres@gsnRightString            = tracer_emiss@units  ; change right title
    mapres@gsnFrame                  = False               ; do not advance frame
    mapres@gsnDraw		     = False	           ; don't draw it yet

    mapres@cnFillOn                  = True
    mapres@cnFillMode                = "CellFill"          ; fill as grid boxes not contours
    mapres@cnLineLabelsOn            = False               ; turn off countour labels
    mapres@cnLinesOn                 = False
    mapres@lbLabelBarOn              = False               ; turn off individual colorbars

    ;mapres@mpLimitMode               ="LatLon"            ; zoom to Australia
    ;  mapres@mpMinLatF               = -45
    ;  mapres@mpMaxLatF               = -10
    ;  mapres@mpMinLonF               = 100
     ; mapres@mpMaxLonF               = 160

    mapres@cnLevelSelectionMode      = "ManualLevels"      ; manually set the contour levels
      mapres@cnMinLevelValF          = 1e09                ; set the minimum contour level
      mapres@cnMaxLevelValF          = 5e10                ; set the maximum contour level
      mapres@cnLevelSpacingF         = 1e10                ; set the interval between contours

    ;-------------------
    ; do the plotting
    ;-------------------
    ;map1 = gsn_csm_contour_map_ce(wks,co2_all(0,:,:),mapres)

    mapres@gsnLeftString            = "spatial sum = "+ SumOrigGrid(0) ; change left title
      map1 = gsn_csm_contour_map_ce(wks,tracer_emiss(0,:,:),mapres)

    mapres@gsnLeftString            = "spatial sum = "+ Sum_Regrid(0) ; change left title
      map2 = gsn_csm_contour_map_ce(wks,emiss_regrid(0,:,:),mapres)

    panel_res                       = True
      panel_res@txString            = "QFED "+ tracername +" emissions"
      panel_res@gsnPanelLabelBar    = True                ; add common colorbar
      panel_res@gsnPanelFigureStrings = (/"qfed high res","qfed low res"/)

    gsn_panel(wks,(/map1,map2/),(/2,1/),panel_res)

  end if    ; PLOT


end
