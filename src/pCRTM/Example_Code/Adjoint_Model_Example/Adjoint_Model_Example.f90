!------------------------------------------------------------------------------
!P+
! NAME:
!       Adjoint_Model_Example
!
! PURPOSE:
!       Program to show how to initialise and run the adjoint component
!       of the prototype CRTM (pCRTM).
!
! CATEGORY:
!       pCRTM
!
! LANGUAGE:
!       Fortran-95
!
! MODULES:
!       Type_Kinds:            Module containing definitions for kinds
!                              of variable types.
!
!       Message_Handler:       Module to define simple error codes and
!                              handle error conditions
!                              USEs: FILE_UTILITY module
!
!       Initialize:            Module for pCRTM initialisation.
!                              USEs: ERROR_HANDLER module
!                                    SPECTRAL_COEFFICIENTS module
!                                    TRANSMITTANCE_COEFFICIENTS module
!
!       Parameters:            Module to hold pCRTM parameter constants
!                              USEs: TYPE_KINDS module
!
!       Adjoint_Model:         Module containing the pCRTM adjoint
!                              component
!                              USEs: TYPE_KINDS module
!                                    ERROR_HANDLER module
!                                    PARAMETERS module
!                                    SPECTRAL_COEFFICIENTS module
!                                    ABSORBER_PROFILE module
!                                    PREDICTORS module
!                                    TRANSMITTANCE module
!                                    RADIANCE module
!                                    FORWARD_MODEL module
! CONTAINS:
!       None.
!
! INCLUDE FILES:
!       Profile.inc:  Include file containing the definition of the test
!                     profile(s) and dimensions.
!
! EXTERNALS:
!       None.
!
! COMMON BLOCKS:
!       None.
!
! FILES ACCESSED:
!       Input spectral coefficient (SpcCoeff) and gas absorption model
!       coefficient (TauCoeff) data files
!
! CREATION HISTORY:
!       Written by:     Paul van Delst, CIMSS/SSEC 12-Jun-2004
!                       paul.vandelst@ssec.wisc.edu
!
!  Copyright (C) 2004 Paul van Delst
!
!  This program is free software; you can redistribute it and/or
!  modify it under the terms of the GNU General Public License
!  as published by the Free Software Foundation; either version 2
!  of the License, or (at your option) any later version.
!
!  This program is distributed in the hope that it will be useful,
!  but WITHOUT ANY WARRANTY; without even the implied warranty of
!  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!  GNU General Public License for more details.
!
!  You should have received a copy of the GNU General Public License
!  along with this program; if not, write to the Free Software
!  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
!P-
!------------------------------------------------------------------------------

PROGRAM Adjoint_Model_Example


  ! ------------
  ! Module usage
  ! ------------

  ! -- Utility modules
  USE Type_Kinds
  USE Message_Handler

  ! -- RTM modules
  USE Initialize
  USE Parameters
  USE Adjoint_Model


  ! ---------------------------
  ! Disable all implicit typing
  ! ---------------------------

  IMPLICIT NONE


  ! --------------------------------------------------
  ! Include the dimension information and profile data
  ! --------------------------------------------------

  INCLUDE 'Profile.inc'


  ! ----------
  ! Parameters
  ! ----------

  CHARACTER( * ), PARAMETER :: PROGRAM_NAME   = 'Adjoint_Model_Example'
  CHARACTER( * ), PARAMETER :: PROGRAM_RCS_ID = &
    '$Id: Adjoint_Model_Example.f90,v 1.5 2006/05/02 14:58:35 dgroff Exp $'
  CHARACTER( * ),  PARAMETER :: PROGRAM_HEADER = &
  '**********************************************************'

  ! -- Surface temperature
  REAL( fp_kind ), DIMENSION( N_PROFILES ) :: SURFACE_TEMPERATURE = (/ 310.00000_fp_kind /)

  ! -- Some angle data
  REAL( fp_kind ), DIMENSION( N_PROFILES ) :: SECANT_VIEW_ANGLE  = (/  1.6655002_fp_kind /)  ! 53.1 deg
  REAL( fp_kind ), DIMENSION( N_PROFILES ) :: SECANT_SOLAR_ANGLE = (/ 12.0_fp_kind /)  ! 85.2 deg


  ! ---------
  ! Variables
  ! ---------

  ! -- Header stuff
  INTEGER         :: pn_pos
  CHARACTER( 80 ) :: pn_fmt

  ! -- Variable dimension determined during initialisation
  INTEGER :: n_Channels  ! L dimension

  ! -- Forward inputs
  REAL( fp_kind ), DIMENSION( : ), ALLOCATABLE :: Surface_Emissivity            ! L*M  
  REAL( fp_kind ), DIMENSION( : ), ALLOCATABLE :: Surface_Reflectivity          ! L*M  

  ! -- Adjoint inputs                                                                                
  REAL( fp_kind ), DIMENSION( :, : ), ALLOCATABLE :: Tau_AD                     ! K x L*M
  REAL( fp_kind ), DIMENSION( :, : ), ALLOCATABLE :: Flux_Tau_AD                ! K x L*M
  REAL( fp_kind ), DIMENSION( :, : ), ALLOCATABLE :: Solar_Tau_AD               ! K x L*M
  REAL( fp_kind ), DIMENSION( : ),    ALLOCATABLE :: Upwelling_Radiance_AD      ! L*M  
  REAL( fp_kind ), DIMENSION( : ),    ALLOCATABLE :: Brightness_Temperature_AD  ! L*M  

  ! -- Other inputs
  INTEGER,         DIMENSION( N_PROFILES )     :: n_Channels_Per_Profile        ! M  
  INTEGER,         DIMENSION( : ), ALLOCATABLE :: Channel_Index                 ! L*M 

  ! -- Forward outputs                                                                                
  REAL( fp_kind ), DIMENSION( :, : ), ALLOCATABLE :: Tau                        ! K x L*M
  REAL( fp_kind ), DIMENSION( :, : ), ALLOCATABLE :: Flux_Tau                   ! K x L*M
  REAL( fp_kind ), DIMENSION( :, : ), ALLOCATABLE :: Solar_Tau                  ! K x L*M
  REAL( fp_kind ), DIMENSION( : ),    ALLOCATABLE :: Upwelling_Radiance         ! L*M  
  REAL( fp_kind ), DIMENSION( : ),    ALLOCATABLE :: Brightness_Temperature     ! L*M  

  ! -- Adjoint outputs
  REAL( fp_kind ), DIMENSION( N_LAYERS, N_PROFILES ) :: Level_Pressure_AD       ! K x M
  REAL( fp_kind ), DIMENSION( N_LAYERS, N_PROFILES ) :: Layer_Pressure_AD       ! K x M
  REAL( fp_kind ), DIMENSION( N_LAYERS, N_PROFILES ) :: Layer_Temperature_AD    ! K x M
  REAL( fp_kind ), DIMENSION( N_LAYERS, N_PROFILES ) :: Layer_Water_Vapor_AD    ! K x M
  REAL( fp_kind ), DIMENSION( N_LAYERS, N_PROFILES ) :: Layer_Ozone_AD          ! K x M

  REAL( fp_kind ), DIMENSION( N_PROFILES ) :: Surface_temperature_AD            ! M

  REAL( fp_kind ), DIMENSION( : ), ALLOCATABLE :: Surface_Emissivity_AD         ! L*M  
  REAL( fp_kind ), DIMENSION( : ), ALLOCATABLE :: Surface_Reflectivity_AD       ! L*M  

  ! -- Optional forward inputs
  REAL( fp_kind ), DIMENSION( : ), ALLOCATABLE :: Solar_Reflectivity            ! L*M  

  ! -- Other optional inputs
  REAL( fp_kind ), DIMENSION( N_PROFILES )     :: Secant_Flux_Angle             ! M

  ! -- Optional adjoint outputs
  REAL( fp_kind ), DIMENSION( : ), ALLOCATABLE :: Solar_Reflectivity_AD         ! L*M  


  ! -- Error status variables
  INTEGER :: Error_Status
  INTEGER :: Allocate_Status


  ! -- Some integers to play around with
  ! -- the number of channels to process
  INTEGER :: n_Channel_Skip
  INTEGER :: n_Channels_to_Process


  ! -- Loop counters
  INTEGER :: l, m, lm


  ! -- Coefficient filenames
  CHARACTER( 256 ) :: SpcCoeff_File
  CHARACTER( 256 ) :: TauCoeff_File



  !#----------------------------------------------------------------------------#
  !#                       -- OUTPUT DESCRIPTIVE HEADER --                      #
  !#----------------------------------------------------------------------------#

  pn_pos = ( LEN( PROGRAM_HEADER ) / 2 ) - &
           ( LEN( PROGRAM_NAME ) / 2 )
  pn_pos = MAX( pn_pos, 0 ) + 5
  WRITE( pn_fmt, '( "( ",i2,"x, a )" )' ) pn_pos

  WRITE( *, '(/5x,a )' ) PROGRAM_HEADER
  WRITE( *, FMT = TRIM( pn_fmt ) ) PROGRAM_NAME
  WRITE( *, '(/5x, " Example program showing how to call the pCRTM Adjoint" )' )
  WRITE( *, '( 5x, "   Component." )' )
  WRITE( *, '(/5x, " $Revision: 1.5 $")' )
  WRITE( *, '( 5x, a )' ) PROGRAM_HEADER



  !#----------------------------------------------------------------------------#
  !#              -- GET THE REQUIRED COEFFICIENT DATAFILE NAMES --             #
  !#----------------------------------------------------------------------------#

  ! ----------------------
  ! The SpcCoeff data file
  ! ----------------------

  WRITE( *, FMT     = '( /5x, "Enter the SpcCoeff filename: " )', &
            ADVANCE = 'NO' )
  READ( *, '( a )' ) SpcCoeff_File
  SpcCoeff_File = ADJUSTL( SpcCoeff_File )


  ! ----------------------
  ! The TauCoeff data file
  ! ----------------------

  WRITE( *, FMT     = '(  5x, "Enter the TauCoeff filename: " )', &
            ADVANCE = 'NO' )
  READ( *, '( a )' ) TauCoeff_File
  TauCoeff_File = ADJUSTL( TauCoeff_File )



  !#----------------------------------------------------------------------------#
  !#                      -- INITIALISE THE pCRTM MODEL --                      # 
  !#                                                                            #
  !#                 This function is in the INITIALIZE module                  #
  !#----------------------------------------------------------------------------#

  WRITE( *, '( /5x, "Initializing the pCRTM..." )' )

  Error_Status = Initialize_RTM( Spectral_File = SpcCoeff_File, &
                                 Tau_File      = TauCoeff_File  )

  IF ( Error_Status /= SUCCESS ) THEN 
     CALL Display_Message( PROGRAM_NAME, &
                           'Error initializing the pCRTM', & 
                            Error_Status)  
   STOP
  END IF



  !#----------------------------------------------------------------------------#
  !#                -- ALLOCATE THE CHANNEL DEPENDENT ARRAYS --                 #
  !#                                                                            #
  !# Rather than hard-wire the code for a particular number of channels, the    #
  !# following allocations are done so that:                                    #
  !#   1) the channel dimension can be determined dynamically based on the      #
  !#      channel dimension of the input coefficient data files, and            #
  !#   2) there is an illustration of the use of the input arguments            #
  !#        n_Channels_per_Profile                                              #
  !#      and                                                                   #
  !#        Channel_Index                                                       #
  !#                                                                            #
  !# So, if the next block of code seems overly obtuse, you can always set the  #
  !# number of channels to some fixed value, declare the channel-dependent      #
  !# arrays accordingly, and avoid the allocations.                             #
  !#----------------------------------------------------------------------------#



  ! ----------------------------------------------
  ! Retrieve the number of channels defined during
  ! the initialisation.
  !
  ! This subroutine is in the PARAMETERS module.
  ! ----------------------------------------------

  CALL Get_Max_n_Channels( n_Channels )


  ! ----------------------------------------------------
  ! Get the number of channels to skip in the processing
  !
  ! This is just to illustrate how what is
  ! contained in the input arrays
  !   n_Channels_per_Profile
  ! and
  !   Channel_Index
  ! controls the channel processing
  ! ----------------------------------------------------

  WRITE( *, FMT     = '( /5x, "Enter the number of channels to skip [1==process all]: " )', &
            ADVANCE = 'NO' )
  READ( *, * ) n_Channel_Skip

  IF ( n_Channel_Skip < 0 ) n_Channel_Skip = 1


  ! -- So... let's skip some channels instead of doing them all
  n_Channels_to_Process = n_Channels / n_Channel_Skip
  IF ( MOD( n_Channels, n_Channel_Skip ) /= 0 ) n_Channels_to_Process = n_Channels_to_Process + 1



  ! ----------------------
  ! Perform the allocation
  ! ----------------------

  ALLOCATE( Surface_Emissivity( n_Channels*N_PROFILES ), &         ! L*M 
            Surface_Reflectivity( n_Channels*N_PROFILES ), &       ! L*M 
            Surface_Emissivity_AD( n_Channels*N_PROFILES ), &      ! L*M 
            Surface_Reflectivity_AD( n_Channels*N_PROFILES ), &    ! L*M 
            Channel_Index( n_Channels*N_PROFILES ), &              ! L*M 
            Tau( N_LAYERS, n_Channels*N_PROFILES ), &              ! K x L*M 
            Flux_Tau( N_LAYERS, n_Channels*N_PROFILES ), &         ! K x L*M 
            Solar_Tau( N_LAYERS, n_Channels*N_PROFILES ), &        ! K x L*M 
            Upwelling_Radiance( n_Channels*N_PROFILES ), &         ! L*M 
            Brightness_Temperature( n_Channels*N_PROFILES ), &     ! L*M 
            Tau_AD( N_LAYERS, n_Channels*N_PROFILES ), &           ! K x L*M 
            Flux_Tau_AD( N_LAYERS, n_Channels*N_PROFILES ), &      ! K x L*M 
            Solar_Tau_AD( N_LAYERS, n_Channels*N_PROFILES ), &     ! K x L*M 
            Upwelling_Radiance_AD( n_Channels*N_PROFILES ), &      ! L*M 
            Brightness_Temperature_AD( n_Channels*N_PROFILES ), &  ! L*M
            Solar_Reflectivity( n_Channels*N_PROFILES ), &         ! L*M 
            Solar_Reflectivity_AD( n_Channels*N_PROFILES ), &      ! L*M 
            STAT = Allocate_Status )

  IF ( Allocate_Status /= 0 ) THEN
     CALL Display_Message( PROGRAM_NAME, &
                           'Error allocating channel-dependent arrays', & 
                            FAILURE )  
   STOP
  END IF  



  !#----------------------------------------------------------------------------#
  !#                   -- FILL THE REMAINING INPUT ARRAYS --                    #
  !#----------------------------------------------------------------------------#

  ! -----------------------------
  ! Surface and flux angle inputs
  ! -----------------------------

  Surface_Emissivity   = 0.6_fp_kind
  Surface_Reflectivity = ONE - Surface_Emissivity

  Solar_Reflectivity = ZERO
  Secant_Flux_Angle  = SECANT_DIFFUSIVITY_ANGLE


  ! -----------------------------
  ! Initialise the adjoint inputs
  ! -----------------------------

  Tau_AD       = ZERO
  Flux_Tau_AD  = ZERO
  Solar_Tau_AD = ZERO

  Upwelling_Radiance_AD = ZERO

  ! -- All adjoints outputs will be wrt Tb
  Brightness_Temperature_AD = ONE


  ! ------------------------------
  ! Initialise the adjoint outputs
  ! ------------------------------

  Level_Pressure_AD       = ZERO
  Layer_Pressure_AD       = ZERO
  Layer_Temperature_AD    = ZERO
  Layer_Water_vapor_AD    = ZERO
  Layer_Ozone_AD          = ZERO
  Surface_Temperature_AD  = ZERO
  Surface_Emissivity_AD   = ZERO
  Surface_Reflectivity_AD = ZERO
  Solar_Reflectivity_AD   = ZERO


  ! --------------------------------------
  ! Process this many channels per profile
  ! --------------------------------------

  n_Channels_per_Profile = n_Channels_to_Process


  ! ---------------------------------
  ! The index of required channels in
  ! the coefficient data structures.
  ! ---------------------------------

  Channel_Index( 1:n_Channels_to_Process*N_PROFILES ) = &
    (/ (( l, l = 1, n_Channels, n_Channel_Skip ), m = 1, N_PROFILES ) /)



  !#----------------------------------------------------------------------------#
  !#                         -- CALL THE ADJOINT MODEL --                       #
  !#                                                                            #
  !#                This function is in the ADJOINT_MODEL module                #
  !#----------------------------------------------------------------------------#

  WRITE( *, '( /5x, "Calling the pCRTM Adjoint component..." )' )

  Error_Status = Compute_RTM_AD( LEVEL_PRESSURE,                    &  ! Input, K x M
                                 LAYER_PRESSURE,                    &  ! Input, K x M
                                 LAYER_TEMPERATURE,                 &  ! Input, K x M
                                 LAYER_WATER_VAPOR,                 &  ! Input, K x M
                                 LAYER_OZONE,                       &  ! Input, K x M   
                                 SURFACE_TEMPERATURE,               &  ! Input, M    
                                 Surface_Emissivity,                &  ! Input, L*M    
                                 Surface_Reflectivity,              &  ! Input, L*M 
                                 Tau_AD, Flux_Tau_AD, Solar_Tau_AD, &  ! Input, K x L*M 
                                 Upwelling_Radiance_AD,             &  ! Input, L*M
                                 Brightness_Temperature_AD,         &  ! Input, L*M
                                 SECANT_VIEW_ANGLE,                 &  ! Input, M
                                 SECANT_SOLAR_ANGLE,                &  ! Input, M   
                                 n_Channels_Per_Profile,            &  ! Input, M
                                 Channel_Index,                     &  ! Input, L*M   
                                 Tau, Flux_Tau, Solar_Tau,          &  ! Output, K x L*M
                                 Upwelling_Radiance,                &  ! Output, L*M  
                                 Brightness_Temperature,            &  ! Output, L*M  
                                 Level_Pressure_AD,                 &  ! Output, K x M
                                 Layer_Pressure_AD,                 &  ! Output, K x M 
                                 Layer_Temperature_AD,              &  ! Output, K x M 
                                 Layer_Water_vapor_AD,              &  ! Output, K x M 
                                 Layer_Ozone_AD,                    &  ! Output, K x M   
                                 Surface_Temperature_AD,            &  ! Output, M     
                                 Surface_Emissivity_AD,             &  ! Output, L*M     
                                 Surface_Reflectivity_AD,           &  ! Output, L*M 
                                 Solar_Reflectivity    = Solar_Reflectivity,    &  ! Optional input, L*M 
                                 Solar_Reflectivity_AD = Solar_Reflectivity_AD, &  ! Optional in/output, L*M 
                                 Secant_Flux_Angle     = Secant_Flux_Angle      )  ! Optional input, M

  IF ( Error_Status /= SUCCESS ) THEN 
     CALL Display_Message( PROGRAM_NAME, &
                           'Error in Compute_RTM_AD call', & 
                            Error_Status )                           
   STOP
  END IF



  !#----------------------------------------------------------------------------#
  !#                        -- OUTPUT RESULTS AND CLEAN UP --                   #
  !#----------------------------------------------------------------------------#

  ! ---------------------------------
  ! Print some brightness temperature
  ! ---------------------------------

  WRITE( *, '( /5x, "Results for ", a, "..." )' ) PROFILE_NAME

  lm = 0
  DO m = 1, N_PROFILES
    DO l = 1, n_Channels_to_Process
      lm = lm + 1

      WRITE( *, '(  5x, "Channel index: ", i4, &
                   &2x, "Tb = ", f7.3, " K", &
                   &2x, "d(Tb)/d(esfc) = ", f7.3, " K" )' ) &
                Channel_Index( lm ), &
                Brightness_Temperature( lm ), &
                Surface_Emissivity_AD(lm)

    END DO
    WRITE( *, '( /5x, "SUM{l=1,",i4,"} d(Tb)/d(Tsfc) = ", f7.3 )' ) &
              n_Channels_to_Process, Surface_Temperature_AD( m )
  END DO


  ! ---------------------------------------
  ! Deallocate the channel dependent arrays
  ! ---------------------------------------

  DEALLOCATE( Surface_Emissivity, &         ! L*M 
              Surface_Reflectivity, &       ! L*M 
              Surface_Emissivity_AD, &      ! L*M 
              Surface_Reflectivity_AD, &    ! L*M 
              Channel_Index, &              ! L*M 
              Tau, &                        ! K x L*M 
              Flux_Tau, &                   ! K x L*M 
              Solar_Tau, &                  ! K x L*M 
              Upwelling_Radiance, &         ! L*M 
              Brightness_Temperature, &     ! L*M 
              Tau_AD, &                     ! K x L*M 
              Flux_Tau_AD, &                ! K x L*M 
              Solar_Tau_AD, &               ! K x L*M 
              Upwelling_Radiance_AD, &      ! L*M 
              Brightness_Temperature_AD, &  ! L*M 
              STAT = Allocate_Status )

  IF ( Allocate_Status /= 0 ) THEN
     CALL Display_Message( PROGRAM_NAME, &
                           'Error deallocating channel-dependent arrays', & 
                            WARNING )  
  END IF


  !#----------------------------------------------------------------------------#
  !#                        -- DESTROY THE pCRTM SPACE --                       # 
  !#                                                                            #
  !#                 This function is in the INITIALIZE module                  #
  !#----------------------------------------------------------------------------#

  WRITE( *, '( /5x, "Destroying the pCRTM space..." )' )

  Error_Status = Destroy_RTM()

  IF ( Error_Status /= SUCCESS ) THEN 
     CALL Display_Message( PROGRAM_NAME, &
                           'Error destroying the pCRTM space', & 
                            Error_Status )
   STOP
  END IF

END PROGRAM Adjoint_Model_Example


!-------------------------------------------------------------------------------
!                          -- MODIFICATION HISTORY --
!-------------------------------------------------------------------------------
!
! $Id: Adjoint_Model_Example.f90,v 1.5 2006/05/02 14:58:35 dgroff Exp $
!
! $Date: 2006/05/02 14:58:35 $
!
! $Revision: 1.5 $
!
! $Name:  $
!
! $State: Exp $
!
! $Log: Adjoint_Model_Example.f90,v $
! Revision 1.5  2006/05/02 14:58:35  dgroff
! - Replaced all references of Error_Handler with Message_Handler
!
! Revision 1.4  2005/02/09 23:50:19  paulv
! - Added header output.
!
! Revision 1.3  2004/12/23 20:11:04  paulv
! - Now using profile data include file.
!
! Revision 1.2  2004/06/13 15:05:04  paulv
! - Added code to initialise the adjoint outputs.
!
! Revision 1.1  2004/06/12 19:29:07  paulv
! Initial checkin.
!
!
!
