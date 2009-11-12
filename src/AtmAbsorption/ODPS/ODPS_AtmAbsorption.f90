!
! ODPS_AtmAbsorption
!
! Module containing routines to compute the optical depth profile
! due to gaseous absorption using the Optical Depth Pressure Space 
! (ODPS) algorithm
!
!
! CREATION HISTORY:
!       Written by:     Yong Han & Yong Chen, JCSDA, NOAA/NESDIS 20-Jun-2008
!            TL,AD:     Tong Zhu, CIRA/CSU@NOAA/NESDIS 06-Jan-2009
!
 
MODULE ODPS_AtmAbsorption

  ! -----------------
  ! Environment setup
  ! -----------------
  ! Module use
  USE Type_Kinds,                ONLY: fp
  USE Message_Handler,           ONLY: SUCCESS, FAILURE, Display_Message
  USE CRTM_Atmosphere_Define,    ONLY: CRTM_Atmosphere_type, H2O_ID
  USE CRTM_AtmAbsorption_Define, ONLY: CRTM_AtmAbsorption_type
  USE CRTM_GeometryInfo_Define,  ONLY: CRTM_GeometryInfo_type
  USE ODPS_Define,               ONLY: ODPS_type,                &
                                       SIGNIFICANCE_OPTRAN
  USE ODPS_TauCoeff,             ONLY: TC 
  USE ODPS_Predictor,            ONLY: Compute_Predictor,        &
                                       Compute_Predictor_TL,     &
                                       Compute_Predictor_AD,     &
                                       Destroy_Predictor,        &
                                       Allocate_Predictor,       &
                                       Destroy_PAFV,             &
                                       Allocate_PAFV,            &
                                       Predictor_type,           &
                                       ODPS_APVariables_type,    &
                                       Get_Component_ID,         &
                                       Compute_Predictor_OPTRAN, &
                                       Compute_Predictor_OPTRAN_TL, &
                                       Compute_Predictor_OPTRAN_AD, &
                                       GROUP_ZSSMIS               , &
                                       GROUP_1                    , &
                                       GROUP_2                    , &
                                       GROUP_3                    , &
                                       MAX_OPTRAN_ORDER           ,  &
                                       MAX_OPTRAN_USED_PREDICTORS
                                        
  USE ODPS_ZAtmAbsorption,       ONLY: Compute_Predictors_zssmis,    &
                                       Compute_Predictors_zssmis_TL, &
                                       Compute_Predictors_zssmis_AD, &
                                       Compute_ODPath_zssmis,    &
                                       Compute_ODPath_zssmis_TL, &
                                       Compute_ODPath_zssmis_AD

  USE CRTM_SensorInput_Define, ONLY: CRTM_SensorInput_type, &
                                     CRTM_SensorInput_Get_Property

  USE CRTM_Parameters, ONLY: ZERO, ONE, TWO, &
                             EARTH_RADIUS, SATELLITE_HEIGHT, &
                             DEGREES_TO_RADIANS, &
                             TOLERANCE, &
                             LIMIT_EXP, LIMIT_LOG

  USE Profile_Utility_Parameters, ONLY: G0, EPS, R_DRYAIR

  ! Disable implicit typing
  IMPLICIT NONE

  ! ------------
  ! Visibilities
  ! ------------
  ! Everything private by default
  PRIVATE
  ! variables and routines from USE modules
  PUBLIC :: Predictor_type
  PUBLIC :: Destroy_Predictor
  PUBLIC :: Allocate_Predictor
  PUBLIC :: Destroy_PAFV
  PUBLIC :: Allocate_PAFV  
  PUBLIC :: ODPS_APVariables_type

  ! Science routines in this modules
  PUBLIC :: ODPS_Compute_AtmAbsorption
  PUBLIC :: ODPS_Compute_AtmAbsorption_TL
  PUBLIC :: ODPS_Compute_AtmAbsorption_AD
  PUBLIC :: ODPS_Compute_Predictors
  PUBLIC :: ODPS_Compute_Predictors_TL
  PUBLIC :: ODPS_Compute_Predictors_AD
  PUBLIC :: Geopotential_Height
  PUBLIC :: Geopotential_Height_TL
  PUBLIC :: Geopotential_Height_AD
    
  ! Internal variable structure
  PUBLIC :: ODPS_AAVariables_type

  ! -----------------
  ! Module parameters
  ! -----------------
  ! RCS Id for the module
  CHARACTER(*), PRIVATE, PARAMETER :: MODULE_RCS_ID = &
  '$Id: ODPS_AtmAbsorption.f90 896 2008-07-1 yong.han@noaa.gov $'

  
  ! ------------------------------------------
  ! Structure definition to hold forward model
  ! variables across FWD, TL, and AD calls
  ! ------------------------------------------
  TYPE :: ODPS_AAVariables_type
    PRIVATE
    INTEGER :: dummy
  END TYPE ODPS_AAVariables_type

  ! Maximum allowed layer optical depth
  REAL(fp), PARAMETER :: MAX_OD     = 20.0_fp

! LOGICAL, PUBLIC, PARAMETER  :: ALLOW_OPTRAN = .FALSE.
  LOGICAL, PUBLIC, PARAMETER  :: ALLOW_OPTRAN = .TRUE.

  ! Parameters used in the geopotential height calculation routines
  ! a factor used in the virtual temperature Tv calculation
  REAL(fp), PARAMETER :: C = (ONE/EPS - ONE) / 1000.0_fp
  ! a factor used in the scale height calculation ( H = CC*Tv)
  REAL(fp), PARAMETER :: CC = 0.001_fp*R_DRYAIR/G0
  ! for using in SUBROUTINE LayerAvg
  REAL(fp), PARAMETER :: SMALLDIFF  = 1.0E-20_fp
  
CONTAINS



!################################################################################
!################################################################################
!##                                                                            ##
!##                         ## PUBLIC MODULE ROUTINES ##                       ##
!##                                                                            ##
!################################################################################
!################################################################################

!------------------------------------------------------------------------------
!
! NAME:
!       ODPS_Compute_AtmAbsorption
!
! PURPOSE:
!       Subroutine to calculate the layer optical depths due to gaseous
!       absorption for a given sensor and channel and atmospheric profile.
!
! CALLING SEQUENCE:
!       CALL ODPS_Compute_AtmAbsorption( TC           , &  ! Input
!                                        ChannelIndex , &  ! Input                    
!                                        Predictor    , &  ! Input                    
!                                        AtmAbsorption, &  ! Output                   
!                                        AAVariables    )  ! Internal variable output 
!
! INPUT ARGUMENTS:
!             TC:        Structure containing Tau coefficient data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(ODPS_TauCoeff_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN OUT)
!
!       ChannelIndex:    Channel index id. This is a unique index associated
!                        with a (supported) sensor channel used to access the
!                        shared coefficient data for a particular sensor's
!                        channel.
!                        See the SensorIndex argument.
!                        UNITS:      N/A
!                        TYPE:       INTEGER
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       Predictor:       Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
! OUTPUT ARGUMENTS:
!        AtmAbsorption:  Structure containing computed optical depth
!                        profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(CRTM_AtmAbsorption_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN OUT)
!
! COMMENTS:
!       Note the INTENT on the structure arguments are IN OUT rather
!       than just OUT. This is necessary because the argument is defined
!       upon input. To prevent memory leaks, the IN OUT INTENT is a must.
!
!------------------------------------------------------------------------------

  SUBROUTINE ODPS_Compute_AtmAbsorption( TC           , &  ! Input
                                         ChannelIndex , &  ! Input
                                         Predictor    , &  ! Input
                                         AtmAbsorption)    ! Output
    ! Arguments
    TYPE(ODPS_type)              , INTENT(IN)     :: TC
    INTEGER                      , INTENT(IN)     :: ChannelIndex
    TYPE(Predictor_type)         , INTENT(IN OUT) :: Predictor
    TYPE(CRTM_AtmAbsorption_type), INTENT(IN OUT) :: AtmAbsorption
    ! Local variables
    INTEGER  :: n_Layers, n_User_Layers
    INTEGER  :: i          ! coefficent index
    INTEGER  :: k          ! Layer index
    INTEGER  :: j          ! Component index
    INTEGER  :: np         ! number of predictors
    REAL(fp) :: OD(Predictor%n_Layers)
    REAL(fp) :: OD_Path(0:Predictor%n_Layers)
    REAL(fp) :: User_OD_Path(0:Predictor%n_User_Layers)
!    REAL(fp) :: Acc_Weighting_OD(Predictor%n_Layers, Predictor%n_User_Layers)
!    INTEGER  :: ODPS2User_Idx(2, Predictor%n_User_Layers)
    INTEGER  :: ODPS2User_Idx(2, 0:Predictor%n_User_Layers)
    REAL(fp) :: OD_tmp
    LOGICAL  :: OPTRAN
    INTEGER  :: j0, js, ComID

    ! ------
    ! Set up
    ! ------
    ! Assign the indices to a short name
    n_Layers = Predictor%n_Layers
    n_User_Layers = Predictor%n_User_Layers
 
    !--------------------------------------------------------
    ! Compute optical path profile using specified algorithm
    !--------------------------------------------------------
    IF(TC%Group_index == GROUP_ZSSMIS)THEN  ! for ZSSMIS
      CALL Compute_ODPath_zssmis(ChannelIndex, &
                                 TC,          &
                                 Predictor,    &
                                 OD_Path)
    ELSE  ! all other sensors

      ! Loop over each tau component for optical depth calculation
      OD = ZERO
      Component_Loop: DO j = 1, Predictor%n_Components

        ! number of predictors for the current component and channel               
        ! Note, TC%n_Predictors(j, ChannelIndex) <= Predictor%n_CP(j).             
        ! For example, if the upper m predictors have zero coefficients,           
        ! then, only coefficients with indexed 1 to (Predictor%n_CP(j) - m)        
        ! are stored and used used in the OD calculations.                         
        np = TC%n_Predictors(j, ChannelIndex)

        ! Check if there is any absorption for the component&channel combination.
        IF( np <= 0 ) CYCLE Component_Loop

        ! set flag for possible OPTRAN algorithm
        ! If this flag is set, this component is computed using OPTRAN algorithm.
        ! Otherwise, it is computed using ODPS algorithm.
        IF( Predictor%OPTRAN .AND. j == TC%OComponent_Index)THEN
           OPTRAN = TC%OSignificance(ChannelIndex) == SIGNIFICANCE_OPTRAN
        ELSE
           OPTRAN = .FALSE.
        END IF
        
        IF(OPTRAN)THEN
          CALL Add_OPTRAN_wloOD(TC,          &   
                               ChannelIndex,  &            
                               Predictor,     &            
                               OD ) 
        ELSE

          ! ODPS algorithm                                                                     
          j0 = TC%Pos_Index(j, ChannelIndex)
          DO i = 1, np
            js = j0+(i-1)*n_Layers-1
            DO k = 1, n_Layers          
              OD(k) = OD(k) + TC%C(js+k)*Predictor%X(k, i, j)
            END DO
          END DO
        
        END IF


      END DO Component_Loop

      !------------------------------------------------------
      ! Compute optical path (level to space) profile
      !------------------------------------------------------ 
      OD_Path(0) = ZERO
      DO k = 1, n_layers
        OD_tmp = OD(k)
        IF(OD(k) < ZERO)THEN
          OD_tmp = ZERO
        ELSE IF(OD(k) > MAX_OD)THEN
          OD_tmp = MAX_OD
        END IF
        OD_Path(k) = OD_Path(k-1) + OD_tmp
      END DO
      
    END IF

    ! Save forward variables
    ! Interpolate the path profile back on the user pressure grids,
    ! Compute layer optical depths (vertical direction)

    IF(Predictor%PAFV%Active)THEN  
      ! save forwad variables
      Predictor%PAFV%OD = OD
      Predictor%PAFV%OD_Path = OD_Path
      ! If interpolation indexes are known
      User_OD_Path(0) = ZERO
      CALL Interpolate_Profile(Predictor%PAFV%ODPS2User_Idx,    &
                               OD_Path,                         &
                               Predictor%Ref_Level_LnPressure,  &
                               Predictor%User_Level_LnPressure, &
                               User_OD_Path)
!      DO k = 1, n_User_layers
!        User_OD_Path(k) = &
!          SUM(Predictor%PAFV%Acc_Weighting_OD(Predictor%PAFV%ODPS2User_Idx(1,k):Predictor%PAFV%ODPS2User_Idx(2,k), k)  &
!        * OD_Path(Predictor%PAFV%ODPS2User_Idx(1,k):Predictor%PAFV%ODPS2User_Idx(2,k)) )
!      END DO
    ELSE ! interpolation indexes are not known

      CALL Compute_Interp_Index(Predictor%Ref_Level_LnPressure, &
                                Predictor%User_Level_LnPressure,&
                                ODPS2User_Idx)  
      CALL Interpolate_Profile(ODPS2User_Idx,                   &
                               OD_Path,                         &
                               Predictor%Ref_Level_LnPressure,  &
                               Predictor%User_Level_LnPressure, &
                               User_OD_Path)
!      CALL LayerAvg( Predictor%User_Level_LnPressure(1:n_User_Layers), & !Predictor%User_LnPressure, & 
!                     Predictor%Ref_Level_LnPressure(1:n_Layers)      , & !Predictor%Ref_LnPressure , & 
!                     Acc_Weighting_OD                                , &                                      
!                     ODPS2User_Idx)
 
!      User_OD_Path(0) = ZERO
!      DO k = 1, n_User_layers
!        User_OD_Path(k) = SUM(Acc_Weighting_OD(ODPS2User_Idx(1,k):ODPS2User_Idx(2,k), k)  &
!                             * OD_Path(ODPS2User_Idx(1,k):ODPS2User_Idx(2,k)) )
!      END DO
      
    END IF

    ! Optical depth profile scaled to zenith.  Note that the scaling
    ! factor is the surface secant zenith angle.
    AtmAbsorption%Optical_Depth = (User_OD_Path(1:n_User_Layers) - &
                                   User_OD_Path(0:n_User_Layers-1)) / &
                                   Predictor%Secant_Zenith_Surface

 
  END SUBROUTINE ODPS_Compute_AtmAbsorption

!------------------------------------------------------------------------------
!
! NAME:
!       ODPS_Compute_AtmAbsorption_TL
!
! PURPOSE:
!       Subroutine to calculate the layer optical depths due to gaseous
!       absorption for a given sensor and channel and atmospheric profile.
!
! CALLING SEQUENCE:
!       CALL ODPS_Compute_AtmAbsorption_TL( TC           ,   &  ! Input
!                                           ChannelIndex ,   &  ! Input                    
!                                           Predictor    ,   &  ! Input                    
!                                           Predictor_TL,    &  ! Input                    
!                                           AtmAbsorption_TL,&  ! Output
!                                           AAVariables)        ! Internal variable output
!
! INPUT ARGUMENTS:
!             TC:        Structure containing Tau coefficient data.   
!                        UNITS:      N/A                              
!                        TYPE:       TYPE(ODPS_TauCoeff_type)         
!                        DIMENSION:  Scalar                           
!                        ATTRIBUTES: INTENT(IN OUT)                   
!
!       ChannelIndex:    Channel index id. This is a unique index associated
!                        with a (supported) sensor channel used to access the
!                        shared coefficient data for a particular sensor's
!                        channel.
!                        See the SensorIndex argument.
!                        UNITS:      N/A
!                        TYPE:       INTEGER
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       Predictor:       Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
! OUTPUT ARGUMENTS:
!        AtmAbsorption:  Structure containing computed optical depth
!                        profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(CRTM_AtmAbsorption_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN OUT)
!
! COMMENTS:
!       Note the INTENT on the structure arguments are IN OUT rather
!       than just OUT. This is necessary because the argument is defined
!       upon input. To prevent memory leaks, the IN OUT INTENT is a must.
!
!------------------------------------------------------------------------------

  SUBROUTINE ODPS_Compute_AtmAbsorption_TL( TC           ,  &  ! Input
                                            ChannelIndex ,    &  ! Input
                                            Predictor    ,    &  ! Input
                                            Predictor_TL,     &  ! Input                 
                                            AtmAbsorption_TL)    ! Output
    ! Arguments
    TYPE(ODPS_type)              , INTENT(IN)     :: TC
    INTEGER                      , INTENT(IN)     :: ChannelIndex
    TYPE(Predictor_type)         , INTENT(IN)     :: Predictor
    TYPE(Predictor_type)         , INTENT(INOUT)  :: Predictor_TL
    TYPE(CRTM_AtmAbsorption_type), INTENT(INOUT)  :: AtmAbsorption_TL
    ! Local variables
    INTEGER  :: n_Layers, n_User_Layers
    INTEGER  :: i          ! coefficent index
    INTEGER  :: k          ! Layer index
    INTEGER  :: j          ! Component index
    INTEGER  :: np         ! number of predictors
    REAL(fp) :: OD_TL(Predictor%n_Layers)  
    REAL(fp) :: OD_Path_TL(0:Predictor%n_Layers)
    REAL(fp) :: User_OD_Path_TL(0:Predictor%n_User_Layers)
    LOGICAL  :: OPTRAN
    INTEGER  :: j0, js

    ! ------
    ! Set up
    ! ------
    ! Assign the indices to a short name
    n_Layers = Predictor%n_Layers
    n_User_Layers = Predictor%n_User_Layers
 
    !--------------------------------------------------------
    ! Compute optical path profile using specified algorithm
    !--------------------------------------------------------
    IF(TC%Group_index == GROUP_ZSSMIS)THEN  ! for ZSSMIS

      CALL Compute_ODPath_zssmis_TL(ChannelIndex,    &
                                    TC,             &
                                    Predictor,       &
                                    Predictor_TL,    & 
                                    OD_Path_TL )
    ELSE  ! all other sensors

      ! Loop over each tau component for optical depth calculation
      OD_TL = ZERO
      Component_Loop: DO j = 1, Predictor%n_Components

        ! number of predictors for the current component and channel               
        ! Note, TC%n_Predictors(j, ChannelIndex) <= Predictor%n_CP(j).             
        ! For example, if the upper m predictors have zero coefficients,           
        ! then, only coefficients with indexed 1 to (Predictor%n_CP(j) - m)        
        ! are stored and used used in the OD calculations.                         
        np = TC%n_Predictors(j, ChannelIndex)

        ! Check if there is any absorption for the component&channel combination.
        IF( np <= 0 ) CYCLE Component_Loop

        ! set flag for possible OPTRAN algorithm
        ! If this flag is set, this component is computed using OPTRAN algorithm.
        ! Otherwise, it is computed using ODPS algorithm.
        IF( Predictor%OPTRAN .AND. j == TC%OComponent_Index)THEN
           OPTRAN = TC%OSignificance(ChannelIndex) == SIGNIFICANCE_OPTRAN
        ELSE
           OPTRAN = .FALSE.
        END IF
        
        IF(OPTRAN)THEN
          CALL Add_OPTRAN_wloOD_TL(TC,       &        
                               ChannelIndex,  &               
                               Predictor,     &               
                               Predictor_TL,  &        
                               OD_TL)
        ELSE

          ! ODPS algorithm                                                                     
          j0 = TC%Pos_Index(j, ChannelIndex)
          DO i = 1, np
            js = j0+(i-1)*n_Layers-1
            DO k = 1, n_Layers          
              OD_TL(k) = OD_TL(k) + TC%C(js+k)*Predictor_TL%X(k, i, j)
            END DO
          END DO
        
        END IF
        
      END DO Component_Loop

      !------------------------------------------------------
      ! Compute optical path (level to space) profile
      !------------------------------------------------------ 
      OD_Path_TL(0) = ZERO
      DO k = 1, n_layers
        IF(Predictor%PAFV%OD(k) < ZERO)THEN
          OD_TL(k) = ZERO
        ELSE IF(Predictor%PAFV%OD(k) > MAX_OD)THEN
          OD_TL(k) = ZERO
        END IF
        OD_Path_TL(k) = OD_Path_TL(k-1) + OD_TL(k)
      END DO
      
    END IF

    ! Interpolate the path profile back on the user pressure grids,
    ! Compute layer optical depths (vertical direction)
    CALL Interpolate_Profile_F1_TL(Predictor%PAFV%ODPS2User_Idx,    &
                                   Predictor%PAFV%OD_Path,          &
                                   Predictor%Ref_Level_LnPressure,  &
                                   Predictor%User_Level_LnPressure, &
                                   OD_Path_TL,                      &
                                   User_OD_Path_TL)
!    User_OD_Path_TL(0) = ZERO
!    DO k = 1, n_User_layers                                                                
!      User_OD_Path_TL(k) = &
!      SUM(Predictor%PAFV%Acc_Weighting_OD(Predictor%PAFV%ODPS2User_Idx(1,k):Predictor%PAFV%ODPS2User_Idx(2,k), k)  &  
!          * OD_Path_TL(Predictor%PAFV%ODPS2User_Idx(1,k):Predictor%PAFV%ODPS2User_Idx(2,k)) )              
!    END DO                                                                                 
 
    AtmAbsorption_TL%Optical_Depth = (User_OD_Path_TL(1:n_User_Layers) - &
                                   User_OD_Path_TL(0:n_User_Layers-1)) / &
                                   Predictor%Secant_Zenith_Surface

 
  END SUBROUTINE ODPS_Compute_AtmAbsorption_TL

!------------------------------------------------------------------------------
!
! NAME:
!       ODPS_Compute_AtmAbsorption_AD
!
! PURPOSE:
!       Subroutine to calculate the layer optical depths due to gaseous
!       absorption for a given sensor and channel and atmospheric profile.
!
! CALLING SEQUENCE:
!       CALL ODPS_Compute_AtmAbsorption_AD( TC           ,    &  ! Input
!                                           ChannelIndex ,    &  ! Input                   
!                                           Predictor    ,    &  ! Input
!                                           AtmAbsorption_AD, &  ! Input
!                                           Predictor_AD    , &  ! Output
!                                           AAVariables )        ! Internal variable output
!
! INPUT ARGUMENTS:
!             TC:        Structure containing Tau coefficient data.   
!                        UNITS:      N/A                              
!                        TYPE:       TYPE(ODPS_TauCoeff_type)         
!                        DIMENSION:  Scalar                           
!                        ATTRIBUTES: INTENT(IN OUT)                   
!
!       ChannelIndex:    Channel index id. This is a unique index associated
!                        with a (supported) sensor channel used to access the
!                        shared coefficient data for a particular sensor's
!                        channel.
!                        See the SensorIndex argument.
!                        UNITS:      N/A
!                        TYPE:       INTEGER
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       Predictor:       Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
! OUTPUT ARGUMENTS:
!        AtmAbsorption:  Structure containing computed optical depth
!                        profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(CRTM_AtmAbsorption_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN OUT)
!
! COMMENTS:
!       Note the INTENT on the structure arguments are IN OUT rather
!       than just OUT. This is necessary because the argument is defined
!       upon input. To prevent memory leaks, the IN OUT INTENT is a must.
!
!------------------------------------------------------------------------------

  SUBROUTINE ODPS_Compute_AtmAbsorption_AD( TC           ,    &  ! Input
                                            ChannelIndex ,    &  ! Input
                                            Predictor    ,    &  ! Input
                                            AtmAbsorption_AD, &  ! Input
                                            Predictor_AD)        ! Output
    ! Arguments
    TYPE(ODPS_type)              , INTENT(IN)     :: TC
    INTEGER                      , INTENT(IN)     :: ChannelIndex
    TYPE(Predictor_type)         , INTENT(IN)     :: Predictor
    TYPE(CRTM_AtmAbsorption_type), INTENT(IN OUT) :: AtmAbsorption_AD
    TYPE(Predictor_type)         , INTENT(IN OUT) :: Predictor_AD
    ! Local variables
    INTEGER  :: n_Layers, n_User_Layers
    INTEGER  :: i          ! coefficent index
    INTEGER  :: k          ! Layer index
    INTEGER  :: j          ! Component index
    INTEGER  :: np         ! number of predictors
    REAL(fp) :: OD_AD(Predictor%n_Layers)                 
    REAL(fp) :: OD_Path_AD(0:Predictor%n_Layers) 
    REAL(fp) :: User_OD_Path_AD(0:Predictor%n_User_Layers)
    LOGICAL  :: OPTRAN
    INTEGER  :: j0, js

    ! ------
    ! Set up
    ! ------
    ! Assign the indices to a short name
    n_Layers = Predictor%n_Layers
    n_User_Layers = Predictor%n_User_Layers
  
    !------- Adjoint part ---------
    
    ! Interpolate the path profile back on the user pressure grids,
    ! Compute layer optical depths (vertical direction)
    User_OD_Path_AD(n_User_Layers) = ZERO
    DO k = n_User_Layers, 1, -1
      User_OD_Path_AD(k) = User_OD_Path_AD(k) &
                           + AtmAbsorption_AD%Optical_Depth(k)/Predictor%Secant_Zenith_Surface
      ! combined with initilization
      User_OD_Path_AD(k-1) = -AtmAbsorption_AD%Optical_Depth(k)/Predictor%Secant_Zenith_Surface
    END DO
    AtmAbsorption_AD%Optical_Depth = ZERO

    OD_Path_AD = ZERO          
    CALL Interpolate_Profile_F1_AD(Predictor%PAFV%ODPS2User_Idx,       &
                                   Predictor%PAFV%OD_Path,             &
                                   Predictor%Ref_Level_LnPressure,     &
                                   Predictor%User_Level_LnPressure,    &
                                   User_OD_Path_AD,                    &
                                   OD_Path_AD )

 
    User_OD_Path_AD(0) = ZERO
 
    !--------------------------------------------------------
    ! Compute optical path profile using specified algorithm
    !--------------------------------------------------------
    IF(TC%Group_index == GROUP_ZSSMIS)THEN  ! for ZSSMIS
      CALL Compute_ODPath_zssmis_AD(ChannelIndex, &
                                    TC,          &
                                    Predictor,    &
                                    OD_Path_AD,   &
                                    Predictor_AD )
    ELSE  ! all other sensors

      !------------------------------------------------------
      ! Compute optical path (level to space) profile
      !------------------------------------------------------

      DO k = n_layers, 1, -1
        OD_Path_AD(k-1) = OD_Path_AD(k-1) + OD_Path_AD(k)
        ! combined with initialization
        OD_AD(k) = OD_Path_AD(k)
        OD_Path_AD(k) = ZERO
        IF(Predictor%PAFV%OD(k) < ZERO)THEN
          OD_AD(k) = ZERO
        ELSE IF(Predictor%PAFV%OD(k) > MAX_OD)THEN
          OD_AD(k) = ZERO
        END IF
      END DO
      OD_Path_AD(0) = ZERO

      ! Loop over each tau component for optical depth calculation

      Component_Loop_AD: DO j = 1, Predictor%n_Components

!        IF(j==4) cycle
        ! number of predictors for the current component and channel               
        ! Note, TC%n_Predictors(j, ChannelIndex) <= Predictor%n_CP(j).             
        ! For example, if the upper m predictors have zero coefficients,           
        ! then, only coefficients with indexed 1 to (Predictor%n_CP(j) - m)        
        ! are stored and used used in the OD calculations.                         
        np = TC%n_Predictors(j, ChannelIndex)

        ! Check if there is any absorption for the component&channel combination.
        IF( np <= 0 ) CYCLE Component_Loop_AD

        IF( Predictor%OPTRAN .AND. j == TC%OComponent_Index)THEN
           OPTRAN = TC%OSignificance(ChannelIndex) == SIGNIFICANCE_OPTRAN
        ELSE
           OPTRAN = .FALSE.
        END IF

       IF(OPTRAN)THEN                                
                                                  
         CALL Add_OPTRAN_wloOD_AD(TC,          &    
                                  ChannelIndex, &             
                                  Predictor,    &             
                                  OD_AD,        &    
                                  Predictor_AD ) 
       ELSE

         ! ODPS algorithm                                                                      
         j0 = TC%Pos_Index(j, ChannelIndex)
         DO i = 1, np
           js = j0+(i-1)*n_Layers-1
           DO k = n_Layers, 1, -1          
             Predictor_AD%X(k, i, j) = Predictor_AD%X(k, i, j) + TC%C(js+k)*OD_AD(k)
           END DO
         END DO
             
       END IF

      END DO Component_Loop_AD
      
    END IF

 
  END SUBROUTINE ODPS_Compute_AtmAbsorption_AD

!------------------------------------------------------------------------------
!
! NAME:
!       Add_OPTRAN_wloOD
!
! PURPOSE:
!       Subroutine to calculate and add the layer optical depths due to water 
!       vapor line absorption.  Note the OD argument is an in/out argument, which
!       may hold optical depth from other absorbers.
!
! CALLING SEQUENCE:
!        CALL Add_OPTRAN_wloOD( TC,            &
!                               ChannelIndex,  &            
!                               Predictor,     &            
!                               OD )                        
!
! INPUT ARGUMENTS:
!          ODPS:         ODPS structure holding tau coefficients
!                        UNITS:      N/A
!                        TYPE:       ODPS_type
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       ChannelIndex:    Channel index id. This is a unique index associated
!                        with a (supported) sensor channel used to access the
!                        shared coefficient data for a particular sensor's
!                        channel.
!                        See the SensorIndex argument.
!                        UNITS:      N/A
!                        TYPE:       INTEGER
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       Predictor:       Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
! IN/OUTPUT ARGUMENTS:
!        OD:             Slant path optical depth profile
!                        UNITS:      N/A
!                        TYPE:       REAL(fp)
!                        DIMENSION:  Rank-1 array (n_Layers)
!                        ATTRIBUTES: INTENT(IN OUT)
!
!
!------------------------------------------------------------------------------

  SUBROUTINE Add_OPTRAN_wloOD( TC,            &
                               ChannelIndex,  &            
                               Predictor,     &            
                               OD )                        
    TYPE(ODPS_type),      INTENT( IN )    :: TC
    INTEGER,              INTENT( IN )    :: ChannelIndex
    TYPE(Predictor_type), INTENT( INOUT ) :: Predictor
    REAL(fp),             INTENT( INOUT ) :: OD(:)                                           
  
    ! Local
    REAL(fp)           :: LN_Chi(TC%n_Layers), coeff(0:MAX_OPTRAN_ORDER)
    REAL(fp)           :: b(TC%n_Layers, 0:MAX_OPTRAN_USED_PREDICTORS)
    REAL(fp)           :: Chi(TC%n_Layers)
    INTEGER            :: np, n_Layers, n_orders, js, i, j, k, ii, jj
    
      ! -----------------------------------------
      ! Check if there is any absorption for this
      ! absorber/channel combination.
      ! -----------------------------------------
      np = TC%OP_Index(0,ChannelIndex)  ! number of predictors
      IF ( np <= 0 ) RETURN

      n_Layers = TC%n_Layers      
      js = TC%OPos_Index(ChannelIndex)
      n_orders = TC%Order(ChannelIndex)
      
      DO i = 0, np
        jj = js + i*(n_orders+1)
        coeff(0:n_orders) = TC%OC(jj:jj+n_orders)
        DO k = 1, n_Layers
          b(k,i) = coeff(0)
          DO j = 1, n_orders
            b(k,i) = b(k,i) + coeff(j)*Predictor%Ap(k, j)
          END DO
        END DO

      END DO

      LN_Chi = b(:,0) 
      DO i = 1, np
        ii = TC%OP_Index(i,ChannelIndex)
        DO k = 1, n_Layers
          LN_Chi(k) = LN_Chi(k) + b(k, i)* Predictor%OX(k, ii) 
        END DO        
      END DO

      DO k = 1, n_Layers
        IF( LN_Chi(k) > LIMIT_EXP ) THEN
          Chi(k) = LIMIT_LOG
        ELSE IF( LN_Chi(k) < -LIMIT_EXP ) THEN
          Chi(k) = ZERO
        ELSE
          Chi(k) = EXP(LN_Chi(k))
        ENDIF
        OD(k) = OD(k) + Chi(k)*Predictor%dA(k)

      END DO

      IF(Predictor%PAFV%OPTRAN)THEN
        Predictor%PAFV%b      = b
        Predictor%PAFV%LN_Chi = LN_Chi 
        Predictor%PAFV%Chi    = Chi 
      END IF
            
   END SUBROUTINE Add_OPTRAN_wloOD

!------------------------------------------------------------------------------
!
! NAME:
!       Add_OPTRAN_wloOD_TL
!
! PURPOSE:
!       Subroutine to calculate and add the layer optical depths due to water 
!       vapor line absorption.  Note the OD argument is an in/out argument, which
!       may hold optical depth from other absorbers.
!
! CALLING SEQUENCE:
!        CALL Add_OPTRAN_wloOD_TL( TC,            &
!                                  ChannelIndex,  &            
!                                  Predictor,     &            
!                                  Predictor_TL,  &            
!                                  OD_TL )                        
!
! INPUT ARGUMENTS:
!          ODPS:         ODPS structure holding tau coefficients
!                        UNITS:      N/A
!                        TYPE:       ODPS_type
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       ChannelIndex:    Channel index id. This is a unique index associated
!                        with a (supported) sensor channel used to access the
!                        shared coefficient data for a particular sensor's
!                        channel.
!                        See the SensorIndex argument.
!                        UNITS:      N/A
!                        TYPE:       INTEGER
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       Predictor:       Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!       Predictor_TL:    Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
! IN/OUTPUT ARGUMENTS:
!        OD_TL:          Slant path optical depth profile
!                        UNITS:      N/A
!                        TYPE:       REAL(fp)
!                        DIMENSION:  Rank-1 array (n_Layers)
!                        ATTRIBUTES: INTENT(IN OUT)
!
!
!------------------------------------------------------------------------------

  SUBROUTINE Add_OPTRAN_wloOD_TL( TC,            &
                               ChannelIndex,     &            
                               Predictor,        &            
                               Predictor_TL,     &
                               OD_TL)                        
    TYPE(ODPS_type),      INTENT( IN )    :: TC
    INTEGER,              INTENT( IN )    :: ChannelIndex
    TYPE(Predictor_type), INTENT( IN )    :: Predictor,       Predictor_TL
    REAL(fp),             INTENT( INOUT ) :: OD_TL(:)                   
  
    ! Local
    REAL(fp)           :: coeff(0:MAX_OPTRAN_ORDER)
    REAL(fp)           :: LN_Chi_TL(TC%n_Layers), b_TL(TC%n_Layers, 0:MAX_OPTRAN_USED_PREDICTORS)
    REAL(fp)           :: chi_TL(TC%n_Layers)
    INTEGER            :: np, n_Layers, n_orders, js, i, j, k, ii, jj

      ! -----------------------------------------
      ! Check if there is any absorption for this
      ! absorber/channel combination.
      ! -----------------------------------------
      np = TC%OP_Index(0,ChannelIndex)  ! number of predictors
      IF ( np <= 0 ) RETURN

      n_Layers = TC%n_Layers      
      js = TC%OPos_Index(ChannelIndex)
      n_orders = TC%Order(ChannelIndex)
   
      DO i = 0, np
        jj = js + i*(n_orders+1)
        coeff(0:n_orders) = TC%OC(jj:jj+n_orders)
        DO k = 1, n_Layers
          b_TL(k,i) = ZERO
          DO j = 1, n_orders
            b_TL(k,i) = b_TL(k,i) + coeff(j)*Predictor_TL%Ap(k, j)
          END DO
        END DO

      END DO

      LN_Chi_TL = b_TL(:,0) 
      DO i = 1, np
        ii = TC%OP_Index(i,ChannelIndex)
        DO k = 1, n_Layers
          LN_Chi_TL(k) = LN_Chi_TL(k) + b_TL(k, i)* Predictor%OX(k, ii) + Predictor%PAFV%b(k, i)* Predictor_TL%OX(k, ii)
        END DO        
      END DO

      DO k = 1, n_Layers
        IF( Predictor%PAFV%LN_Chi(k) > LIMIT_EXP ) THEN
          Chi_TL(k) = ZERO
        ELSE IF( Predictor%PAFV%LN_Chi(k) < -LIMIT_EXP ) THEN
          Chi_TL(k) = ZERO
        ELSE
          Chi_TL(k) = Predictor%PAFV%Chi(k) * LN_Chi_TL(k)
        ENDIF
        OD_TL(k) = OD_TL(k) + Chi_TL(k)*Predictor%dA(k) + Predictor%PAFV%Chi(k)*Predictor_TL%dA(k)

      END DO
      
   END SUBROUTINE Add_OPTRAN_wloOD_TL


!------------------------------------------------------------------------------
!
! NAME:
!       Add_OPTRAN_wloOD_AD
!
! PURPOSE:
!       Subroutine to calculate and add the layer optical depths due to water 
!       vapor line absorption.  Note the OD argument is an in/out argument, which
!       may hold optical depth from other absorbers.
!
! CALLING SEQUENCE:
!        CALL Add_OPTRAN_wloOD_AD( TC,            &
!                                  ChannelIndex,  &            
!                                  Predictor,     &            
!                                  OD_AD,         &
!                                  Predictor_AD )                        
!
! INPUT ARGUMENTS:
!          ODPS:         ODPS structure holding tau coefficients
!                        UNITS:      N/A
!                        TYPE:       ODPS_type
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       ChannelIndex:    Channel index id. This is a unique index associated
!                        with a (supported) sensor channel used to access the
!                        shared coefficient data for a particular sensor's
!                        channel.
!                        See the SensorIndex argument.
!                        UNITS:      N/A
!                        TYPE:       INTEGER
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!       Predictor:       Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN)
!
!        OD_AD:          Slant path optical depth profile
!                        UNITS:      N/A
!                        TYPE:       REAL(fp)
!                        DIMENSION:  Rank-1 array (n_Layers)
!                        ATTRIBUTES: INTENT(IN)
!
! IN/OUTPUT ARGUMENTS:
!       Predictor_AD:    Structure containing the integrated absorber and
!                        predictor profile data.
!                        UNITS:      N/A
!                        TYPE:       TYPE(Predictor_type)
!                        DIMENSION:  Scalar
!                        ATTRIBUTES: INTENT(IN OUT)
!
!------------------------------------------------------------------------------

  SUBROUTINE Add_OPTRAN_wloOD_AD( TC,            &
                                  ChannelIndex,  &            
                                  Predictor,     &            
                                  OD_AD,         &
                                  Predictor_AD )                        
    TYPE(ODPS_type),      INTENT( IN )    :: TC
    INTEGER,              INTENT( IN )    :: ChannelIndex
    TYPE(Predictor_type), INTENT( IN )    :: Predictor
    REAL(fp),             INTENT( INOUT ) :: OD_AD(:)
    TYPE(Predictor_type), INTENT( INOUT ) :: Predictor_AD                             
  
    ! Local
    REAL(fp)           :: coeff(0:MAX_OPTRAN_ORDER)
    REAL(fp)           :: LN_Chi_AD(TC%n_Layers), b_AD(TC%n_Layers, 0:MAX_OPTRAN_USED_PREDICTORS)
    REAL(fp)           :: Chi_AD(TC%n_Layers)
    INTEGER            :: np, n_Layers, n_orders, js, i, j, k, ii, jj

      !------ Forward part for LN_Chi, b -----------

      ! -----------------------------------------
      ! Check if there is any absorption for this
      ! absorber/channel combination.
      ! -----------------------------------------
      np = TC%OP_Index(0,ChannelIndex)  ! number of predictors
      IF ( np <= 0 ) RETURN

      n_Layers = TC%n_Layers
      js = TC%OPos_Index(ChannelIndex)
      n_orders = TC%Order(ChannelIndex)

      !------ Adjoint part ----------------------
    
      ! -----------------------------------------
      ! Check if there is any absorption for this
      ! absorber/channel combination.
      ! -----------------------------------------

      Chi_AD = ZERO
      !LN_Chi_AD = ZERO
      DO k = n_Layers, 1, -1
      
        Chi_AD(k) = Chi_AD(k) + OD_AD(k) * Predictor%dA(k)
        Predictor_AD%dA(k) = Predictor_AD%dA(k) + OD_AD(k) * Predictor%PAFV%Chi(k)
        IF( Predictor%PAFV%LN_Chi(k) > LIMIT_EXP ) THEN
          Chi_AD(k) = ZERO
        ELSE IF( Predictor%PAFV%LN_Chi(k) < -LIMIT_EXP ) THEN
          Chi_AD(k) = ZERO
        ELSE
          LN_Chi_AD(k) = Predictor%PAFV%Chi(k) * Chi_AD(k)  ! combinded with initialization for LN_Chi_AD(k)
        ENDIF
      END DO

      DO i = 1, np
        ii = TC%OP_Index(i,ChannelIndex)
        DO k = n_Layers, 1, -1
          b_AD(k, i) = LN_Chi_AD(k) * Predictor%OX(k, ii)  ! Combinded with initialization for b_AD
          Predictor_AD%OX(k, ii) = Predictor_AD%OX(k, ii) + LN_Chi_AD(k)*Predictor%PAFV%b(k, i)
        END DO        
      END DO
      b_AD(:,0) = LN_Chi_AD
!!    LN_Chi_AD = ZERO  !! no need since it will not be used again

      DO i = 0, np
        jj = js + i*(n_orders+1)
        coeff(0:n_orders) = TC%OC(jj:jj+n_orders)
        DO k = n_Layers, 1, -1
          DO j = 1, n_orders
            Predictor_AD%Ap(k, j) = Predictor_AD%Ap(k, j) + coeff(j)*b_AD(k,i)
          END DO
          b_AD(k,i) = ZERO
        END DO

      END DO

   END SUBROUTINE Add_OPTRAN_wloOD_AD


!--------------------------------------------------------------------------------
!
! NAME:
!       ODPS_Compute_Predictors
!
! PURPOSE:
!       Subroutine to calculate the gas absorption model predictors. It first
!       Interpolates the user temperature and absorber profiles on the
!       internal pressure grids and then call the predictor computation
!       routine to compute the predictors
!
! CALLING SEQUENCE:
!       CALL ODPS_Compute_Predictors ( TC,           &  ! Input 
!                                      Atm,          &  ! Input
!                                      GeoInfo,      &  ! Input                        
!                                      Predictor,    &  ! Output                  
!                                      APV           )  ! Internal variable output
!
! INPUT ARGUMENTS:
!       TC        :     Structure containing Tau coefficient data.    
!                       UNITS:      N/A                               
!                       TYPE:       TYPE(ODPS_TauCoeff_type)          
!                       DIMENSION:  Scalar                            
!                       ATTRIBUTES: INTENT(IN)                    
!
!       Atm       :     CRTM Atmosphere structure containing the atmospheric
!                       state data.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_Atmosphere_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
!       GeoInfo     :   CRTM_GeometryInfo structure containing the 
!                       view geometry information.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_GeometryInfo_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
! OUTPUT ARGUMENTS:
!       Predictor:      Predictor structure containing the integrated absorber
!                       and predictor profiles.
!                       UNITS:      N/A
!                       TYPE:       TYPE(Predictor_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN OUT)
!
!--------------------------------------------------------------------------------

  SUBROUTINE ODPS_Compute_Predictors(SensorInput,  &
                                     TC,  &
                                     Atm,          &    
                                     GeoInfo,      &  
                                     Predictor)
    ! Arguments
    TYPE(CRTM_SensorInput_type)  , INTENT(IN)     :: SensorInput
    TYPE(ODPS_type)              , INTENT(IN)     :: TC
    TYPE(CRTM_Atmosphere_type)   , INTENT(IN)     :: Atm
    TYPE(CRTM_GeometryInfo_type) , INTENT(IN)     :: GeoInfo
    TYPE(Predictor_type)         , INTENT(IN OUT) :: Predictor

    ! Local variables
    INTEGER  :: idx(1)
    REAL(fp) :: Absorber(Predictor%n_Layers, TC%n_Absorbers)
    REAL(fp) :: Temperature(Predictor%n_Layers)
    REAL(fp) :: Ref_LnPressure(Predictor%n_Layers)
    REAL(fp) :: User_LnPressure(Atm%n_layers)
    REAL(fp) :: SineAng
    REAL(fp) :: ODPS_sfc_fraction, Z_Offset, s 
    REAL(fp) :: Z(0:Predictor%n_Layers)  ! Heights of pressure levels
    REAL(fp) :: Acc_Weighting(Predictor%n_User_Layers, Predictor%n_Layers)
    INTEGER  :: interp_index(2, Predictor%n_Layers)
    ! absorber index mapping from ODPS to user 
    INTEGER  :: Idx_map(TC%n_Absorbers), H2O_idx
    INTEGER  :: j, jj, k, n_ODPS_Layers, n_User_Layers, ODPS_sfc_idx
    ! SSMIS SensorInput data
    REAL(fp) :: Be, CosBK, Doppler_Shift
    
    
    n_ODPS_Layers = Predictor%n_Layers
    n_User_Layers = Atm%n_layers
    ! Set pressure profiles for interpolations
    Ref_LnPressure = LOG(TC%Ref_Pressure)
    User_LnPressure = LOG(Atm%Pressure(1:n_User_Layers))
    Predictor%Ref_Level_LnPressure = LOG(TC%Ref_Level_Pressure)
    IF(Atm%Level_Pressure(0) <= ZERO)THEN
      ! In this bad case, the top pressure level is set to the half of the next-to-top pressure level
      Predictor%User_Level_LnPressure(0) = LOG(Atm%Level_Pressure(1)/TWO)
    ELSE
      Predictor%User_Level_LnPressure(0) = LOG(Atm%Level_Pressure(0))
    END IF
    Predictor%User_Level_LnPressure(1:n_User_Layers) = LOG(Atm%Level_Pressure(1:n_User_Layers))
    
    ! Find the index at which the ODPS layer contains the user surface pressure level. Then
    ! compute the fraction of the portion between the lower boundary of the ODPS layer and
    ! the user surface pressure level 
    ODPS_sfc_idx = n_ODPS_Layers
    ODPS_sfc_fraction = ZERO
    IF(TC%Ref_Level_Pressure(n_ODPS_Layers) > Atm%Level_Pressure(n_User_Layers))THEN
      DO k = n_ODPS_Layers, 0, -1
        IF(TC%Ref_Level_Pressure(k) < Atm%Level_Pressure(n_User_Layers))THEN
          ODPS_sfc_idx = k+1
          ODPS_sfc_fraction = (Predictor%Ref_Level_LnPressure(ODPS_sfc_idx) - &
                               Predictor%User_Level_LnPressure(n_User_Layers)) /&
                              (Predictor%Ref_Level_LnPressure(ODPS_sfc_idx) - &
                               Predictor%Ref_Level_LnPressure(k))
          EXIT
        END IF
      END DO
    END IF
               
    !-----------------------------------------------------------
    ! Interpolate temperautre profile on internal pressure grids
    !-----------------------------------------------------------
    CALL LayerAvg( Ref_LnPressure   , & 
                   User_LnPressure  , &   
                   Acc_Weighting    , &                                                    
                   interp_index) 

    DO k = 1, n_ODPS_Layers                                                                
       Temperature(k) = SUM(Acc_Weighting(interp_index(1,k):interp_index(2,k), k)  &  
                           * Atm%Temperature(interp_index(1,k):interp_index(2,k)) )              
    END DO                                                                                 
    
    !-----------------------------------------------------------
    ! Interpolate absorber profiles on internal pressure grids
    !-----------------------------------------------------------
    DO j = 1,TC%n_Absorbers
      Idx_map(j) = -1
      DO jj=1, Atm%n_Absorbers
       IF( Atm%Absorber_ID(jj) == TC%Absorber_ID(j) ) THEN
        Idx_map(j) = jj
        EXIT
       END IF
      END DO
 
      ! save index for water vapor absorption
      IF(TC%Absorber_ID(j) == H2O_ID)THEN
        H2O_idx = j
      END IF
      IF(Idx_map(j) > 0)THEN

        DO k = 1, n_ODPS_Layers                                                            
            Absorber(k,j) = SUM(Acc_Weighting(interp_index(1,k):interp_index(2,k), k)  &
                               * Atm%Absorber(interp_index(1,k):interp_index(2,k), Idx_map(j)) )          
        END DO                                                                             

        DO k=1, n_ODPS_Layers

          IF (Absorber(k,j) <= TOLERANCE ) Absorber(k,j) = TOLERANCE
          IF (Absorber(k,j) < TC%Min_Absorber(k,j) ) Absorber(k,j) = TC%Min_Absorber(k,j)
          IF (Absorber(k,j) > TC%Max_Absorber(k,j) ) Absorber(k,j) = TC%Max_Absorber(k,j)

        END DO
      ELSE ! when the profile is missing, use the referece profile 
        Absorber(:, j) = TC%Ref_Absorber(:, j)
      END IF

    END DO
 
    !-----------------------------------------------
    ! Compute height dependent secant zenith angles
    !-----------------------------------------------
    ! Compute geopotential height, which starts from ODPS surface pressure level
    CALL Geopotential_Height( TC%Ref_Level_Pressure,           &  
                              TC%Ref_Temperature,              &      
                              TC%Ref_Absorber(:, H2O_idx),     &      
                              ZERO,                            &      
                              Z) 
    ! Adjust ODPS surface height for the user surface height. The adjustment includes two parts:       
    ! (1) the delta Z from the ODPS surface pressure to the user surface pressure  
    ! (2) the user-given surface height                                            
    IF(TC%Ref_Level_Pressure(n_ODPS_Layers) >= Atm%Level_Pressure(n_User_Layers))THEN
      Z_Offset = -(Z(ODPS_sfc_idx) + ODPS_sfc_fraction*(Z(ODPS_sfc_idx-1)-Z(ODPS_sfc_idx))) &
                 + GeoInfo%Surface_Altitude
    ELSE
      ! For the case in which the user surface pressure is larger than the ODPS surface pressure,
      ! the ODPS surface is adjusted for a surface pressure 1013 mb, regardless the user supplied 
      ! surface height.
      Z_Offset = CC*TC%Ref_Temperature(n_ODPS_Layers) &  ! scale height
                 *LOG(1013.0_fp / TC%Ref_Level_Pressure(n_ODPS_Layers))
    END IF
    Z = Z + Z_Offset

    s = (EARTH_RADIUS + GeoInfo%Surface_Altitude)*SIN(GeoInfo%Sensor_Zenith_Angle*DEGREES_TO_RADIANS)

    DO k = 1, n_ODPS_Layers
      SineAng = s /(EARTH_RADIUS + Z(k))
      Predictor%Secant_Zenith(k) = ONE / SQRT(ONE - SineAng*SineAng)
    END DO

    ! store the surface secant zenith angle
    Predictor%Secant_Zenith_Surface = GeoInfo%Secant_Sensor_Zenith

    !-------------------------------------------
    ! Compute predictor
    !-------------------------------------------
    
    IF(TC%Group_index == GROUP_ZSSMIS)THEN  ! for ZSSMIS
      CALL CRTM_SensorInput_Get_Property( SensorInput%SSMIS, &
                                          Field_Strength = Be, &
                                          COS_ThetaB     = CosBk, &
                                          Doppler_Shift  = Doppler_Shift )
      CALL Compute_Predictors_zssmis(Temperature,                              &
                                     Be,             &
                                     CosBK,          &
                                     Doppler_Shift,  &
                                     Predictor%Secant_Zenith,&
                                     Predictor)
    
    ELSE  ! all other sensors
      CALL Compute_Predictor( TC%Group_index,         &
                              Temperature,            &
                              Absorber,               &              
                              TC%Ref_Level_Pressure,  &      
                              TC%Ref_Temperature,     &      
                              TC%Ref_Absorber,        &   
                              Predictor%Secant_Zenith,&                    
                              Predictor )
      IF( ALLOW_OPTRAN .AND. TC%n_OCoeffs > 0 )THEN

         CALL Compute_Predictor_OPTRAN( Temperature, &
                                        Absorber(:, H2O_idx),   &
                                        TC%Ref_Level_Pressure,  &
                                        TC%Ref_Pressure,        &
                                        Predictor%Secant_Zenith,&
                                        TC%Alpha,               &
                                        TC%Alpha_C1,            &
                                        TC%Alpha_C2,            &
                                        Predictor )

       END IF
    END IF
     
    IF(Predictor%PAFV%Active)THEN
      Predictor%PAFV%Temperature  = Temperature               
      Predictor%PAFV%Absorber     = Absorber
      Predictor%PAFV%interp_index = interp_index
      Predictor%PAFV%Acc_Weighting= Acc_Weighting
      Predictor%PAFV%idx_map      = idx_map
      Predictor%PAFV%H2O_idx      = H2O_idx
      Predictor%PAFV%Ref_LnPressure = Ref_LnPressure
      Predictor%PAFV%User_LnPressure = User_LnPressure
      ! Set and save the interpolation index array for absorption
      ! calculations. Since the indexes do not depend on channel but
      ! the absorption calculations do, put the index calculation here
      ! can improve efficency.
      CALL Compute_Interp_Index(Predictor%Ref_Level_LnPressure ,  &
                                Predictor%User_Level_LnPressure,  &
                                Predictor%PAFV%ODPS2User_Idx) 
!      CALL LayerAvg( Predictor%User_Level_LnPressure(1:n_User_Layers), & !Predictor%User_LnPressure , & 
!                     Predictor%Ref_Level_LnPressure(1:n_ODPS_Layers) , & !Predictor%Ref_LnPressure , &
!                     Predictor%PAFV%Acc_Weighting_OD, &                                      
!                     Predictor%PAFV%ODPS2User_Idx)
    END IF 
                    

 
  END SUBROUTINE ODPS_Compute_Predictors     

!--------------------------------------------------------------------------------
!
! NAME:
!       ODPS_Compute_Predictors_TL
!
! PURPOSE:
!       Subroutine to calculate the gas absorption model predictors. It first
!       Interpolates the user temperature and absorber profiles on the
!       internal pressure grids and then call the predictor computation
!       routine to compute the predictors
!
! CALLING SEQUENCE:
!       CALL ODPS_Compute_Predictors_TL ( TC,           &  ! Input
!                                      Atm,             &  ! Input
!                                      GeoInfo,         &  ! Input                        
!                                      Predictor,       &  ! Input
!                                      Atm_TL,          &  ! Input
!                                      Predictor_TL,    &  ! Output
!                                      APV)             &  ! Internal variable output
!
! INPUT ARGUMENTS:
!       TC        :     Structure containing Tau coefficient data.    
!                       UNITS:      N/A                               
!                       TYPE:       TYPE(ODPS_TauCoeff_type)          
!                       DIMENSION:  Scalar                            
!                       ATTRIBUTES: INTENT(IN)                    
!
!       Atm       :     CRTM Atmosphere structure containing the atmospheric
!                       state data.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_Atmosphere_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
!       Atm_TL    :     CRTM Atmosphere structure containing the atmospheric
!                       state data.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_Atmosphere_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
!       GeoInfo     :   CRTM_GeometryInfo structure containing the 
!                       view geometry information.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_GeometryInfo_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
!       Predictor:      Predictor structure containing the integrated absorber
!                       and predictor profiles.
!                       UNITS:      N/A
!                       TYPE:       TYPE(Predictor_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
! OUTPUT ARGUMENTS:
!       Predictor_TL:   Predictor structure containing the integrated absorber
!                       and predictor profiles.
!                       UNITS:      N/A
!                       TYPE:       TYPE(Predictor_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN OUT)
!
!--------------------------------------------------------------------------------

  SUBROUTINE ODPS_Compute_Predictors_TL(SensorInput,    &
                                        TC,             &
                                        Atm,            &    
                                        GeoInfo,        &
                                        Predictor,      &
                                        Atm_TL,         & 
                                        Predictor_TL)
 
    TYPE(CRTM_SensorInput_type)  , INTENT(IN)     :: SensorInput
    TYPE(ODPS_type)              , INTENT(IN)     :: TC
    TYPE(CRTM_Atmosphere_type)   , INTENT(IN)     :: Atm,          Atm_TL
    TYPE(CRTM_GeometryInfo_type) , INTENT(IN)     :: GeoInfo
    TYPE(Predictor_type)         , INTENT(IN)     :: Predictor
    TYPE(Predictor_type)         , INTENT(IN OUT) :: Predictor_TL

    ! Local variables
    INTEGER  :: idx(1)
    REAL(fp) :: Absorber_TL(Predictor%n_Layers, TC%n_Absorbers)
    REAL(fp) :: Temperature_TL(Predictor%n_Layers)
    ! absorber index mapping from ODPS to user 
    INTEGER  :: Idx_map(TC%n_Absorbers), H2O_idx
    INTEGER  :: j, jj, k, n_ODPS_Layers
    ! SSMIS SensorInput data
    REAL(fp) :: Be, CosBK, Doppler_Shift

    n_ODPS_Layers = Predictor%n_Layers
 
    !-----------------------------------------------------------
    ! Interpolate temperautre profile on internal pressure grids
    !-----------------------------------------------------------
    DO k = 1, n_ODPS_Layers                                                                
       Temperature_TL(k) = &
         SUM(Predictor%PAFV%Acc_Weighting(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k), k)  &  
             * Atm_TL%Temperature(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k)) )              
    END DO                                                                                 
 
    !-----------------------------------------------------------
    ! Interpolate absorber profiles on internal pressure grids
    !-----------------------------------------------------------
    H2O_idx = Predictor%PAFV%H2O_idx
    Idx_map = Predictor%PAFV%Idx_map

    DO j = 1,TC%n_Absorbers
      IF(idx_map(j) > 0)THEN
      
        DO k = 1, n_ODPS_Layers                                                            
           Absorber_TL(k,j) = &
            SUM(Predictor%PAFV%Acc_Weighting(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k), k)  &
                * Atm_TL%Absorber(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k), Idx_map(j)) )          
        END DO                                                                             

        DO k=1, n_ODPS_Layers
          IF(Predictor%PAFV%Absorber(k,j) <= TOLERANCE ) Absorber_TL(k,j) = ZERO
 
        END DO
      ELSE ! when the profile is missing, use the referece profile 
        Absorber_TL(:, j) = ZERO
      END IF

    END DO

    !-------------------------------------------
    ! Compute predictor
    !-------------------------------------------
    IF(TC%Group_index == GROUP_ZSSMIS)THEN  ! for ZSSMIS
      CALL CRTM_SensorInput_Get_Property( SensorInput%SSMIS, &
                                          Field_Strength = Be, &
                                          COS_ThetaB     = CosBk, &
                                          Doppler_Shift  = Doppler_Shift )
      CALL Compute_Predictors_zssmis_TL(Predictor%PAFV%Temperature,           &
                                        Be,            &   
                                        CosBK,         &   
                                        Doppler_Shift, &   
                                        Predictor%Secant_Zenith,           &
                                        Temperature_TL,                    &
                                        Predictor_TL)

    ELSE  ! all other sensors
      CALL Compute_Predictor_TL(TC%Group_index,          &
                              Predictor%PAFV%Temperature,&
                              Predictor%PAFV%Absorber,   &              
                              TC%Ref_Level_Pressure,     &      
                              TC%Ref_Temperature,        &      
                              TC%Ref_Absorber,           &   
                              Predictor%Secant_Zenith,   &                    
                              Predictor,                 &
                              Temperature_TL,            &
                              Absorber_TL,               & 
                              Predictor_TL )
      IF( ALLOW_OPTRAN .AND. TC%n_OCoeffs > 0)THEN

         CALL Compute_Predictor_OPTRAN_TL( Predictor%PAFV%Temperature,       &
                                        Predictor%PAFV%Absorber(:, H2O_idx), &
                                        TC%Ref_Level_Pressure,  &
                                        TC%Ref_Pressure,        &
                                        Predictor%Secant_Zenith,&
                                        TC%Alpha,               &
                                        TC%Alpha_C1,            &
                                        TC%Alpha_C2,            &
                                        Predictor,              &
                                        Temperature_TL,         &
                                        Absorber_TL(:, H2O_idx),&
                                        Predictor_TL )

       END IF
    END IF
    
 
  END SUBROUTINE ODPS_Compute_Predictors_TL     

!--------------------------------------------------------------------------------
!
! NAME:
!       ODPS_Compute_Predictors_AD
!
! PURPOSE:
!       Subroutine to calculate the gas absorption model predictors. It first
!       Interpolates the user temperature and absorber profiles on the
!       internal pressure grids and then call the predictor computation
!       routine to compute the predictors
!
! CALLING SEQUENCE:
!       CALL ODPS_Compute_Predictors_AD (TC,            &  ! Input
!                                      Atm,             &  ! Input
!                                      GeoInfo,         &  ! Input
!                                      Predictor,       &  ! Input                     
!                                      Predictor_AD,    &  ! Input
!                                      Atm_AD,          &  ! Output
!                                      APV )            &  ! Internal variable output
!
! INPUT ARGUMENTS:
!       TC        :     Structure containing Tau coefficient data.    
!                       UNITS:      N/A                               
!                       TYPE:       TYPE(ODPS_TauCoeff_type)          
!                       DIMENSION:  Scalar                            
!                       ATTRIBUTES: INTENT(IN)                    
!
!       Atm       :     CRTM Atmosphere structure containing the atmospheric
!                       state data.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_Atmosphere_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
!       GeoInfo     :   CRTM_GeometryInfo structure containing the 
!                       view geometry information.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_GeometryInfo_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
!       Predictor:      Predictor structure containing the integrated absorber
!                       and predictor profiles.
!                       UNITS:      N/A
!                       TYPE:       TYPE(Predictor_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
!       Predictor_AD:   Predictor structure containing the integrated absorber
!                       and predictor profiles.
!                       UNITS:      N/A
!                       TYPE:       TYPE(Predictor_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN)
!
! OUTPUT ARGUMENTS:
!
!       Atm_AD    :     CRTM Atmosphere structure containing the atmospheric
!                       state data.
!                       UNITS:      N/A
!                       TYPE:       TYPE(CRTM_Atmosphere_type)
!                       DIMENSION:  Scalar
!                       ATTRIBUTES: INTENT(IN OUT)
!
!--------------------------------------------------------------------------------

  SUBROUTINE ODPS_Compute_Predictors_AD(SensorInput,    &
                                        TC,             &
                                        Atm,            &    
                                        GeoInfo,        &
                                        Predictor,      &
                                        Predictor_AD,   &
                                        Atm_AD)

    TYPE(CRTM_SensorInput_type)  , INTENT(IN)     :: SensorInput
    TYPE(ODPS_type)              , INTENT(IN)     :: TC
    TYPE(CRTM_Atmosphere_type)   , INTENT(IN)     :: Atm
    TYPE(CRTM_GeometryInfo_type) , INTENT(IN)     :: GeoInfo
    TYPE(Predictor_type)         , INTENT(IN)     :: Predictor
    TYPE(Predictor_type)         , INTENT(IN OUT) :: predictor_AD
    TYPE(CRTM_Atmosphere_type)   , INTENT(IN OUT) :: Atm_AD

    ! Local variables
    INTEGER  :: idx(1)
    REAL(fp) :: Absorber_AD(Predictor%n_Layers, TC%n_Absorbers)
    REAL(fp) :: Temperature_AD(Predictor%n_Layers)
    ! absorber index mapping from ODPS to user 
    INTEGER  :: Idx_map(TC%n_Absorbers), H2O_idx
    INTEGER  :: j, jj, k, n_ODPS_Layers
    ! SSMIS SensorInput data
    REAL(fp) :: Be, CosBK, Doppler_Shift

 
    !-----------------------------------------------------------
    ! Initialization of forward model part
    !-----------------------------------------------------------

    n_ODPS_Layers = Predictor%n_Layers
 
    ! initialization
    Temperature_AD = ZERO
    Absorber_AD    = ZERO
    
    H2O_idx = Predictor%PAFV%H2O_idx
    Idx_map = Predictor%PAFV%Idx_map

    !-----------------------------------------------------------
    ! adjoint part
    !-----------------------------------------------------------

    !-------------------------------------------
    ! Compute predictor
    !-------------------------------------------
    IF(TC%Group_index == GROUP_ZSSMIS)THEN  ! for ZSSMIS
      CALL CRTM_SensorInput_Get_Property( SensorInput%SSMIS, &
                                          Field_Strength = Be, &
                                          COS_ThetaB     = CosBk, &
                                          Doppler_Shift  = Doppler_Shift )
      CALL Compute_Predictors_zssmis_AD(Predictor%PAFV%Temperature,          &
                                        Be,           &
                                        CosBK,        & 
                                        Doppler_Shift,& 
                                        Predictor%Secant_Zenith,  &
                                        Predictor_AD,             &
                                        Temperature_AD )

    ELSE  ! all other sensors

      ! If the C-OPTRAN water vapor line algorithm is set (indicated by n_PCeooffs > 0),
      ! then compute predictors for OPTRAN water vapor line absorption.
      IF( ALLOW_OPTRAN .AND. TC%n_OCoeffs > 0 )THEN

         CALL Compute_Predictor_OPTRAN_AD( Predictor%PAFV%Temperature,         &
                                        Predictor%PAFV%Absorber(:, H2O_idx),   &
                                        TC%Ref_Level_Pressure,  &
                                        TC%Ref_Pressure,        &
                                        Predictor%Secant_Zenith,&
                                        TC%Alpha,               &
                                        TC%Alpha_C1,            &
                                        TC%Alpha_C2,            &
                                        Predictor,              &
                                        Predictor_AD,           &
                                        Temperature_AD,         &
                                        Absorber_AD(:, H2O_idx) )

      END IF

      CALL Compute_Predictor_AD( TC%Group_index,         &
                              Predictor%PAFV%Temperature,&
                              Predictor%PAFV%Absorber,   &              
                              TC%Ref_Level_Pressure,     &      
                              TC%Ref_Temperature,        &      
                              TC%Ref_Absorber,           &   
                              Predictor%Secant_Zenith,   &                    
                              Predictor,                 &
                              Predictor_AD,              &
                              Temperature_AD,            &
                              Absorber_AD )
    END IF
    
     
    !-----------------------------------------------------------
    ! Interpolate absorber profiles on internal pressure grids
    !-----------------------------------------------------------
    DO j = TC%n_Absorbers, 1, -1
      IF(idx_map(j) > 0)THEN
       
        DO k=1, n_ODPS_Layers
          IF(Predictor%PAFV%Absorber(k,j) <= TOLERANCE ) Absorber_AD(k,j) = ZERO
        END DO
 
        DO k = n_ODPS_Layers, 1, -1                                                            
           Atm_AD%Absorber(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k), Idx_map(j)) = &
              Atm_AD%Absorber(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k), Idx_map(j)) &
            + Predictor%PAFV%Acc_Weighting(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k), k) &
            * Absorber_AD(k,j)
        END DO                                                                             
   
      ELSE ! when the profile is missing, use the referece profile 
        Absorber_AD(:, j) = ZERO
      END IF
    END DO                

    !-----------------------------------------------------------
    ! Interpolate temperautre profile on internal pressure grids
    !-----------------------------------------------------------
 
    DO k = n_ODPS_Layers, 1, -1                                                                
      Atm_AD%Temperature(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k)) = &
         Atm_AD%Temperature(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k))  &
       + Predictor%PAFV%Acc_Weighting(Predictor%PAFV%interp_index(1,k):Predictor%PAFV%interp_index(2,k), k) &
       * Temperature_AD(k)
    
    END DO                                                                                 

    Temperature_AD = ZERO
    Absorber_AD    = ZERO
    
 
  END SUBROUTINE ODPS_Compute_Predictors_AD

!--------------------------------------------------------------------------------
!S+
! NAME:
!       Geopotential_Height
!
! PURPOSE:
!       Routine to calculate geopotential height using the hypsometric
!       equation.
!
! CALLING SEQUENCE:
!       CALL Geopotential_Height( Level_Pressure,                                    &  ! Input
!                                 Temperature,                                       &  ! Input                      
!                                 Water_Vapor,                                       &  ! Input                      
!                                 Surface_Height,                                    &  ! input                      
!                                 Level_Height)                                                           
!
! INPUT ARGUMENTS:
!       Level_Pressure:            Level Pressures, which are the boundaries of of the
!                                  atmospheric layers for the Temperature and Water_vapor arrays 
!                                  UNITS:      hectoPascals, hPa
!                                  TYPE:       REAL(fp)
!                                  DIMENSION:  Rank-1 (0:n_layers)
!                                  ATTRIBUTES: INTENT(IN)
!
!       Temperature:               Layer Temperature.
!                                  UNITS:      Kelvin, K
!                                  TYPE:       REAL(fp)
!                                  DIMENSION:  Rank-1 (n_layers)
!                                  ATTRIBUTES: INTENT(IN)
!
!       Surface_Height:            Height of Level_Pressure(n_layer)
!                                  input arrays. 
!                                  UNITS:      km.
!                                  TYPE:       REAL(fp)
!                                  DIMENSION:  Scalar
!                                  ATTRIBUTES: INTENT(IN)
!
!
!       Water_Vapor:               Layer water vapor mixing radio
!                                  UNITS:      g/kg
!                                  TYPE:       REAL(fp)
!                                  DIMENSION:  Same as Temperature
!                                  ATTRIBUTES: INTENT(IN)
!
! OUTPUT ARGUMENTS:
!       Level_Height:              Geopotential Heights of the input Pressure levels.
!                                  UNITS:      metres, m
!                                  TYPE:       REAL(fp)
!                                  DIMENSION:  Same as input Pressure
!                                  ATTRIBUTES: INTENT(OUT)
!
!
!
! CREATION HISTORY:
!       Written by:     Yong Han, NOAA/NESDIS 5-Feb-2008
!S-
!--------------------------------------------------------------------------------

  SUBROUTINE Geopotential_Height( Level_Pressure,           &  ! Input
                                  Temperature,              &  ! Input
                                  Water_Vapor,              &  ! Input
                                  Surface_Height,           &  ! input
                                  Level_Height)                ! Output
  
    ! Arguments
    REAL(fp),               INTENT(IN)  :: Level_Pressure(0:)
    REAL(fp),               INTENT(IN)  :: Temperature(:)
    REAL(fp),               INTENT(IN)  :: Water_Vapor(:)
    REAL(fp),               INTENT(IN)  :: Surface_Height
    REAL(fp),               INTENT(OUT) :: Level_Height(0:)

    ! Function result
    REAL(fp) :: Tv, H
    INTEGER  :: k, n_Layers

    n_Layers =  SIZE(Temperature)
    Level_Height(n_layers) = Surface_Height
    DO k = n_Layers, 1, -1
      ! virtual temperature computed using an approximation of the exact formula:
      !  Tv = T*(1+w/epsilon)/(1+w), where w is the water vapor mixing ratio
      Tv = Temperature(k)*(ONE + C*Water_Vapor(k)) 
      H  = CC*Tv
      Level_Height(k-1) = Level_Height(k) + H*LOG(Level_Pressure(k)/Level_Pressure(k-1))
    END DO

  END SUBROUTINE Geopotential_Height     

  SUBROUTINE Geopotential_Height_TL( Level_Pressure,           &  ! Input
                                     Temperature,              &  ! Input
                                     Water_Vapor,              &  ! Input
                                     Surface_Height,           &  ! input
                                     Temperature_TL,           &  ! input
                                     Water_Vapor_TL,           &  ! input
                                     Level_Height_TL)             ! Output
  
    ! Arguments
    REAL(fp),               INTENT(IN)  :: Level_Pressure(0:)
    REAL(fp),               INTENT(IN)  :: Temperature(:)
    REAL(fp),               INTENT(IN)  :: Water_Vapor(:)
    REAL(fp),               INTENT(IN)  :: Surface_Height
    REAL(fp),               INTENT(IN)  :: Temperature_TL(:)
    REAL(fp),               INTENT(IN)  :: Water_Vapor_TL(:)
    REAL(fp),               INTENT(OUT) :: Level_Height_TL(0:)

    ! Function result
    REAL(fp) :: Tv_TL, H_TL
    INTEGER  :: k, n_Layers

    n_Layers =  SIZE(Temperature)
    
    Level_Height_TL(n_layers) = ZERO    
    DO k = n_Layers, 1, -1
      ! virtual temperature computed using an approximation of the exact formula:
      !  Tv = T*(1+w/epsilon)/(1+w), where w is the water vapor mixing ratio
      Tv_TL = Temperature_TL(k)*(ONE + C*Water_Vapor(k)) &
             +Temperature(k)*C*Water_Vapor_TL(k) 

      H_TL = CC*Tv_TL
            
      Level_Height_TL(k-1) = Level_Height_TL(k) &
                           + H_TL*LOG(Level_Pressure(k)/Level_Pressure(k-1))
            
    END DO

  END SUBROUTINE Geopotential_Height_TL    

  SUBROUTINE Geopotential_Height_AD( Level_Pressure,           &  ! Input
                                     Temperature,              &  ! Input
                                     Water_Vapor,              &  ! Input
                                     Surface_Height,           &  ! input
                                     Level_Height_AD,          &  ! input
                                     Temperature_AD,           &  ! output
                                     Water_Vapor_AD)              ! output
  
    ! Arguments
    REAL(fp),               INTENT(IN)     :: Level_Pressure(0:)
    REAL(fp),               INTENT(IN)     :: Temperature(:)
    REAL(fp),               INTENT(IN)     :: Water_Vapor(:)
    REAL(fp),               INTENT(IN)     :: Surface_Height
    REAL(fp),               INTENT(INOUT)  :: Level_Height_AD(0:)
    REAL(fp),               INTENT(INOUT)  :: Temperature_AD(:)
    REAL(fp),               INTENT(INOUT)  :: Water_Vapor_AD(:)

    ! Function result
    REAL(fp) :: Tv_AD, H_AD
    INTEGER  :: k, n_Layers

    n_Layers =  SIZE(Temperature)
    
    DO k = 1, n_Layers
      ! note, direct assignments for Tv_AD & H_AD are used below since they
      ! are not cumulative  
      H_AD = Level_Height_AD(k-1)*LOG(Level_Pressure(k)/Level_Pressure(k-1))
      Level_Height_AD(k) = Level_Height_AD(k-1)
      Level_Height_AD(k-1) = ZERO
      
      Tv_AD = CC*H_AD
      
      Temperature_AD(k) = Temperature_AD(k) + Tv_AD*(ONE + C*Water_Vapor(k)) 
      Water_Vapor_AD(k) = Water_Vapor_AD(k) + Temperature(k)*C*Tv_AD
     
    END DO
    Level_Height_AD(n_layers) = ZERO
     

  END SUBROUTINE Geopotential_Height_AD    

!---------------------------------------------------------------------------------------------  
! NAME: Interpolate_Profile                                                                      
!                                                                                                 
! PURPOSE:
!    Given x and u that are ascending arrays, it interpolates y with the abscissa x
!    on the abscissa u using the following algorithm:
!       y_int(i) = y(1)  if u(i) < x(1)
!       y_int(i) = y(nx) if u(i) > x(nx)
!       y_int(i) = y(ix1) + (y(ix2)-y(ix1))*(u(i) - x(ix1))/(x(ix2)-x(ix1))
!                        if x(ix1) <= u(i) <= x(ix2)
!
!    IThe index array interp_index contains the following content 
!
!      interp_index(1, i) = 1 and interp_index(2, i) = 1, if u(i) < x(1)
!      interp_index(1, i) = nx and interp_index(2, i) = nx, if u(i) > x(nx), 
!                                                          where nx = SIZE(x)
!      x(interp_index(1, i)) <= u(i) <= x(interp_index(2, i)) if x(1) <= u(i) <= x(nx)
!
! CALLING SEQUENCE:
!            CALL Interpolate_Profile(interp_index, y, x, u, y_int)
!
! INPUT ARGUMENTS:
!       y:            The data array to be interpolated.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       x:            The abscissa values for y and they must be monotonically 
!                     ascending.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       u:            The abscissa values for the results
!                     and they must be monotonically ascending
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!    interp_index:    The index array of dimension (nu x 2), where nu = SIZE(u) 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-2
!                     ATTRIBUTES: INTENT(IN)                         
!
! OUTPUT ARGUMENTS:
!       y_int:        The array contains the results 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-1
!                     ATTRIBUTES: INTENT(OUT)                         
!
! RESTRICTIONS:
!     To be efficient, this routine does not check that x and u are both
!     monotonically ascending and the index bounds.
!
! CREATION HISTORY:
!       Written by:     Yong Han, 10-Dec-2008
!-----------------------------------------------------------------------------------

  !----------------------------------------------------------------------------
  !  Interpolation routine with interperlation index array already calculated.
  !----------------------------------------------------------------------------
  SUBROUTINE Interpolate_Profile(interp_index, y, x, u, y_int)
    ! Arguments
    INTEGER,  DIMENSION(:,:), INTENT(IN)  :: interp_index
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: y
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: u
    REAL(fp), DIMENSION(:),   INTENT(OUT) :: y_int
    ! Local variables
    INTEGER :: i, n, k1, k2

    n = SIZE(interp_index, DIM=2)
    DO i = 1, n
      k1 = interp_index(1, i)
      k2 = interp_index(2, i)
      IF( k1 == k2)THEN
        y_int(i) = y(k1)
      ELSE
        CALL Interp_linear(y(k1), x(k1), y(k2), x(k2), u(i), y_int(i))
      END IF
    END DO

  END SUBROUTINE Interpolate_Profile


!---------------------------------------------------------------------------------------------  
! NAME: Interpolate_Profile_TL
!                                                                                                 
! PURPOSE:
!     The Tangent_Linear routine of Interpolate_Profile
! CALLING SEQUENCE:
!           CALL Interpolate_Profile_F1_TL(interp_index, y, x, u, y_TL, y_int_TL)
!      OR   CALL Interpolate_Profile_F2_TL(interp_index, y, x, u, y_TL, u_TL, y_int_TL)
!      OR   CALL Interpolate_Profile_F3_TL(interp_index, y, x, u, y_TL, x_TL, y_int_TL)
!
! INPUT ARGUMENTS:
!       y:            The data array to be interpolated.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       x:            The abscissa values for y and they must be monotonically 
!                     ascending.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       u:            The abscissa values for the results
!                     and they must be monotonically ascending
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       y_TL:         The Tangent-linear data array of y
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       u_TL:         The Tangent-linear data array of u
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       x_TL:         The Tangent-linear data array of x
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!    interp_index:    The index array of dimension (nu x 2), where nu = SIZE(u) 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-2
!                     ATTRIBUTES: INTENT(IN)                         
!
! OUTPUT ARGUMENTS:
!       y_int_TL:     The Tangent-linear array of y_int 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-1
!                     ATTRIBUTES: INTENT(OUT)                         
!
! RESTRICTIONS:
!     To be efficient, this routine does not check that x and u are both
!     monotonically ascending and the index bounds.
!
! CREATION HISTORY:
!       Written by:     Yong Han, 10-Dec-2008
!-----------------------------------------------------------------------------------
    
  SUBROUTINE Interpolate_Profile_F1_TL(interp_index, y, x, u, y_TL, y_int_TL)
    ! Arguments
    INTEGER,  DIMENSION(:,:), INTENT(IN)  :: interp_index
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: y
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: u
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: y_TL
    REAL(fp), DIMENSION(:),   INTENT(OUT) :: y_int_TL
    ! Local variables
    INTEGER :: i, n, k1, k2

    n = SIZE(interp_index, DIM=2)
    DO i = 1, n
      k1 = interp_index(1, i)
      k2 = interp_index(2, i)
      IF( k1 == k2)THEN
        y_int_TL(i) = y_TL(k1)
      ELSE
        CALL Interp_linear_F1_TL(y(k1), x(k1), y(k2), x(k2), u(i), y_TL(k1), y_TL(k2), y_int_TL(i))
      END IF
    END DO

  END SUBROUTINE Interpolate_Profile_F1_TL

  SUBROUTINE Interpolate_Profile_F2_TL(interp_index, y, x, u, y_TL, u_TL, y_int_TL)
    ! Arguments
    INTEGER,  DIMENSION(:,:), INTENT(IN)  :: interp_index
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: y
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: u
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: y_TL
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: u_TL
    REAL(fp), DIMENSION(:),   INTENT(OUT) :: y_int_TL
    ! Local variables
    INTEGER :: i, n, k1, k2

    n = SIZE(interp_index, DIM=2)
    DO i = 1, n
      k1 = interp_index(1, i)
      k2 = interp_index(2, i)
      IF( k1 == k2)THEN
        y_int_TL(i) = y_TL(k1)
      ELSE
        CALL Interp_linear_F2_TL(y(k1), x(k1), y(k2), x(k2), u(i), y_TL(k1), y_TL(k2), u_TL(i), y_int_TL(i))
      END IF
    END DO

  END SUBROUTINE Interpolate_Profile_F2_TL

  SUBROUTINE Interpolate_Profile_F3_TL(interp_index, y, x, u, y_TL, x_TL, y_int_TL)
    ! Arguments
    INTEGER,  DIMENSION(:,:), INTENT(IN)  :: interp_index
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: y
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: u
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: y_TL
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: x_TL
    REAL(fp), DIMENSION(:),   INTENT(OUT) :: y_int_TL
    ! Local variables
    INTEGER :: i, n, k1, k2

    n = SIZE(interp_index, DIM=2)
    DO i = 1, n
      k1 = interp_index(1, i)
      k2 = interp_index(2, i)
      IF( k1 == k2)THEN
        y_int_TL(i) = y_TL(k1)
      ELSE
        CALL Interp_linear_F3_TL(y(k1), x(k1), y(k2), x(k2), u(i), y_TL(k1), x_TL(k1), y_TL(k2), x_TL(k2), y_int_TL(i))
      END IF
    END DO

  END SUBROUTINE Interpolate_Profile_F3_TL

!---------------------------------------------------------------------------------------------  
! NAME: Interpolate_Profile_AD
!                                                                                                 
! PURPOSE:
!     The Adjoint routine of Interpolate_Profile
!
! CALLING SEQUENCE:
!            CALL Interpolate_Profile_F1_AD(interp_index, y, x, u, y_int_AD, y_AD)
!    OR      CALL Interpolate_Profile_F2_AD(interp_index, y, x, u, y_int_AD, y_AD, u_AD)
!    OR      CALL Interpolate_Profile_F3_AD(interp_index, y, x, u, y_int_AD, y_AD, x_AD)
!
! INPUT ARGUMENTS:
!       y:            The data array to be interpolated.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       x:            The abscissa values for y and they must be monotonically 
!                     ascending.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       u:            The abscissa values for the results
!                     and they must be monotonically ascending
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       y_int_AD:     The Adjoint array of y_int 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-1
!                     ATTRIBUTES: INTENT(IN)                         
!
!    interp_index:    The index array of dimension (nu x 2), where nu = SIZE(u) 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-2
!                     ATTRIBUTES: INTENT(IN)                         
!
! OUTPUT ARGUMENTS:
!       y_AD:         The Adjoint data array of y
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       u_AD:         The Adjoint data array of u
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       x_AD:         The Adjoint data array of x
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
! RESTRICTIONS:
!     To be efficient, this routine does not check that x and u are both
!     monotonically ascending and the index bounds.
!
! CREATION HISTORY:
!       Written by:     Yong Han, 10-Dec-2008
!-----------------------------------------------------------------------------------
    
  SUBROUTINE Interpolate_Profile_F1_AD(interp_index, y, x, u, y_int_AD, y_AD)
    ! Arguments
    INTEGER,  DIMENSION(:,:), INTENT(IN)      :: interp_index
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: y
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: u
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: y_int_AD
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: y_AD
    ! Local variables
    INTEGER :: i, n, k1, k2

    n = SIZE(interp_index, DIM=2)
    DO i = n, 1, -1
      k1 = interp_index(1, i)
      k2 = interp_index(2, i)
      IF( k1 == k2)THEN
        y_AD(k1) = y_AD(k1) + y_int_AD(i)
        y_int_AD(i) = ZERO
      ELSE
        CALL Interp_linear_F1_AD(y(k1), x(k1), y(k2), x(k2), u(i), y_int_AD(i), y_AD(k1), y_AD(k2))
      END IF
    END DO

  END SUBROUTINE Interpolate_Profile_F1_AD

  SUBROUTINE Interpolate_Profile_F2_AD(interp_index, y, x, u, y_int_AD, y_AD, u_AD)
    ! Arguments
    INTEGER,  DIMENSION(:,:), INTENT(IN)      :: interp_index
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: y
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: u
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: y_int_AD
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: y_AD
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: u_AD
    ! Local variables
    INTEGER :: i, n, k1, k2

    n = SIZE(interp_index, DIM=2)
    DO i = n, 1, -1
      k1 = interp_index(1, i)
      k2 = interp_index(2, i)
      IF( k1 == k2)THEN
        y_AD(k1) = y_AD(k1) + y_int_AD(i)
        y_int_AD(i) = ZERO
      ELSE
        CALL Interp_linear_F2_AD(y(k1), x(k1), y(k2), x(k2), u(i), y_int_AD(i), y_AD(k1), y_AD(k2), u_AD(i))
      END IF
    END DO

  END SUBROUTINE Interpolate_Profile_F2_AD

  SUBROUTINE Interpolate_Profile_F3_AD(interp_index, y, x, u, y_int_AD, y_AD, x_AD)
    ! Arguments
    INTEGER,  DIMENSION(:,:), INTENT(IN)      :: interp_index
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: y
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)      :: u
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: y_int_AD
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: y_AD
    REAL(fp), DIMENSION(:),   INTENT(IN OUT)  :: x_AD
    ! Local variables
    INTEGER :: i, n, k1, k2

    n = SIZE(interp_index, DIM=2)
    DO i = n, 1, -1
      k1 = interp_index(1, i)
      k2 = interp_index(2, i)
      IF( k1 == k2)THEN
        y_AD(k1) = y_AD(k1) + y_int_AD(i)
        y_int_AD(i) = ZERO
      ELSE
        CALL Interp_linear_F3_AD(y(k1), x(k1), y(k2), x(k2), u(i), y_int_AD(i), y_AD(k1), x_AD(k1), y_AD(k2), x_AD(k2))
      END IF
    END DO

  END SUBROUTINE Interpolate_Profile_F3_AD

!---------------------------------------------------------------------------------------------  
! NAME: Compute_Interp_Index                                                                      
!                                                                                                 
! PURPOSE:
!    Given x and u that are ascending arrays, it computes an index array, interp_index,
!    such that
!    
!      interp_index(i, 1) = 1 and interp_index(i, 2) = 1, if u(i) < x(1)
!      interp_index(i, 1) = nx and interp_index(i, 2) = nx, if u(i) > x(nx), 
!                                                          where nx = SIZE(x)
!      x(interp_index(i, 1)) <= u(i) <= x(interp_index(i, 2)) if x(1) <= u(i) <= x(nx)
!           
! CALLING SEQUENCE:
!            CALL Compute_Interp_Index(x, u, interp_index)
!
! INPUT ARGUMENTS:
!       x:            The abscissa values for the data to be interpolated and
!                     they must be monotonically ascending.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
!       u:            The abscissa values on which the data are interpolated
!                     they must be monotonically ascending
!                     the elements of array x.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1                        
!                     ATTRIBUTES: INTENT(IN)                   
!
! OUTPUT ARGUMENTS:
!       interp_index: The index array of dimension (nu x 2), where nu = SIZE(u) 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-2
!                     ATTRIBUTES: INTENT(OUT)                         
!
! RESTRICTIONS:
!     To be efficient, this routine does not check that x and u are both
!     monotonically ascending and the index bounds.
!
! CREATION HISTORY:
!       Written by:     Yong Han, 07-May-2004
!-----------------------------------------------------------------------------------

  SUBROUTINE Compute_Interp_Index(x, u, interp_index)
    ! Arguments
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: x
    REAL(fp), DIMENSION(:),   INTENT(IN)  :: u
    INTEGER,  DIMENSION(:,:), INTENT(OUT) :: interp_index
    ! Local variables
    INTEGER :: nx, nu, ix, iu, j, k1, k2

    nx = SIZE(x)
    nu = SIZE(u)

    ! Set the indexes to 1 for the elements in u that are smaller than x(1)
    k1 = nu + 1
    LessThan_Loop: DO iu = 1, nu
      IF(u(iu) < x(1))THEN
        interp_index(1, iu) = 1
        interp_index(2, iu) = 1
      ELSE
        k1 = iu
        EXIT LessThan_Loop
      END IF
    END DO LessThan_Loop

    ! Set the indexes to nx for the elements in u that are larger than x(nx)
    k2 = 0
    GreaterThan_Loop: DO iu = nu, k1, -1
      IF(u(iu) > x(nx))THEN
        interp_index(1, iu) = nx
        interp_index(2, iu) = nx
      ELSE
        k2 = iu
        EXIT GreaterThan_Loop
      END IF
    END DO GreaterThan_Loop

    ! Set the indexes for the elements in u that are in the range
    ! between x1(1) and x(nx)
    j = 1
    Outer_Loop: DO iu = k1, k2
      Inner_Loop: DO ix = j, nx-1
        IF(u(iu) >= x(ix) .AND. u(iu) <= x(ix+1))THEN
          interp_index(1, iu) = ix
          interp_index(2, iu) = ix+1
          j = ix
          EXIT Inner_Loop
        ENDIF
      END DO Inner_Loop
    END DO Outer_Loop
  
  END SUBROUTINE Compute_Interp_Index


  !---------------------------------------------
  ! Function for two points linear interpolation
  !---------------------------------------------
  SUBROUTINE Interp_linear(y1, x1, y2, x2, x, y)
    REAL(fp), INTENT(IN)  :: y1, x1, y2, x2, x
    REAL(fp), INTENT(OUT) :: y
    y = y1 + (y2-y1)*(x - x1)/(x2 - x1)
  END SUBROUTINE Interp_linear


  SUBROUTINE Interp_linear_F1_TL(y1, x1, y2, x2, x, y1_TL, y2_TL, y_TL)
    REAL(fp), INTENT(IN)  :: y1, x1, y2, x2, x, y1_TL, y2_TL
    REAL(fp), INTENT(OUT) :: y_TL
    y_TL = y1_TL + (y2_TL-y1_TL)*(x - x1)/(x2 - x1)
  END SUBROUTINE Interp_linear_F1_TL


  SUBROUTINE Interp_linear_F1_AD(y1, x1, y2, x2, x, y_AD, y1_AD, y2_AD)
    REAL(fp), INTENT(IN)     :: y1, x1, y2, x2, x
    REAL(fp), INTENT(IN OUT) :: y_AD
    REAL(fp), INTENT(IN OUT) :: y1_AD, y2_AD
    ! Local variables
    REAL(fp) :: fac
    fac = (x - x1)/(x2 - x1)  
    y1_AD = y1_AD + (ONE - fac)*y_AD
    y2_AD = y2_AD + fac*y_AD  
    y_AD = ZERO
  END SUBROUTINE Interp_linear_F1_AD

  SUBROUTINE Interp_linear_F2_TL(y1, x1, y2, x2, x, y1_TL, y2_TL, x_TL, y_TL)
    REAL(fp), INTENT(IN)  :: y1, x1, y2, x2, x
    REAL(fp), INTENT(IN)  :: y1_TL, y2_TL, x_TL
    REAL(fp), INTENT(OUT) :: y_TL
    y_TL = y1_TL + ( (y2_TL-y1_TL)*(x - x1) + x_TL*(y2-y1) )/(x2 - x1)
  END SUBROUTINE Interp_linear_F2_TL

  SUBROUTINE Interp_linear_F2_AD(y1, x1, y2, x2, x, y_AD, y1_AD, y2_AD, x_AD)
    REAL(fp), INTENT(IN)  :: y1, x1, y2, x2, x
    REAL(fp), INTENT(INOUT) :: y_AD
    REAL(fp), INTENT(INOUT) :: y1_AD, y2_AD, x_AD
    ! Local variables
    REAL(fp) :: fac
    fac = (x - x1)/(x2 - x1)  
    
    y1_AD = y1_AD + (ONE - fac)*y_AD
    y2_AD = y2_AD + fac*y_AD  
    x_AD  = x_AD  + y_AD*(y2-y1)/(x2 - x1)   
    y_AD = ZERO
       
  END SUBROUTINE Interp_linear_F2_AD

  SUBROUTINE Interp_linear_F3_TL(y1, x1, y2, x2, x, y1_TL, x1_TL, y2_TL, x2_TL, y_TL)
    REAL(fp), INTENT(IN)  :: y1, x1, y2, x2, x
    REAL(fp), INTENT(IN)  :: y1_TL, x1_TL, y2_TL, x2_TL
    REAL(fp), INTENT(OUT) :: y_TL
    y_TL = y1_TL + ( (y2_TL-y1_TL) - (x2_TL-x1_TL)*(y2-y1)/(x2 - x1) )*(x - x1)/(x2-x1)
    
  END SUBROUTINE Interp_linear_F3_TL

  SUBROUTINE Interp_linear_F3_AD(y1, x1, y2, x2, x, y_AD, y1_AD, x1_AD, y2_AD, x2_AD)
    REAL(fp), INTENT(IN)  :: y1, x1, y2, x2, x
    REAL(fp), INTENT(INOUT) :: y_AD
    REAL(fp), INTENT(INOUT) :: y1_AD, x1_AD, y2_AD, x2_AD
    ! Local variables
    REAL(fp) :: fac, fac2
    
    fac = (x - x1)/(x2 - x1)  
    fac2 = ((y2-y1)/(x2 - x1))*fac
    
    y1_AD = y1_AD + (ONE - fac)*y_AD
    y2_AD = y2_AD + fac*y_AD  
    x1_AD  = x1_AD  + fac2*y_AD
    x2_AD  = x2_AD  - fac2*y_AD
       
    y_AD = ZERO
       
  END SUBROUTINE Interp_linear_F3_AD

!--------------------------------------------------------------------------------
!
! NAME:
!       LayerAvg 
!
! PURPOSE:
!    Given px1 (output domain) and px2 (input domain) that are ascending arrays, 
!    it computes the accumulated weighting factors for interpolation from input
!    to output domainsan, and the index array, interp_index, such that output 
!    variable 
!      to(jo) = sum(pz(interp_index(1,jo):interp_index(2,jo),jo) &
!                   *(ti(interp_index(1,jo):interp_index(2,jo))))

! 
! CALLING SEQUENCE:
!       CALL LayerAvg(PX1,PX2,PZ,Interp_index)
!
! INPUT ARGUMENTS:
!       PX1:          The abscissa values for the target data (output domain) and
!                     they must be monotonically ascending (e.g. lnP; in increasing values).
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1 (KN1)                       
!                     ATTRIBUTES: INTENT(IN)       
!       PX2:          The abscissa values for the source data (input domain) and
!                     they must be monotonically ascending (e.g. lnP; in increasing values).
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-1 (KN2)                       
!                     ATTRIBUTES: INTENT(IN)       
!
! OUTPUT ARGUMENTS:
!       PZ:           Resultant accumulated weighting factors for
!                     interpolation from input to output domains.
!                     UNITS:      N/A                            
!                     TYPE:       fp         
!                     DIMENSION:  rank-2 (KN2,KN1)                       
!                     ATTRIBUTES: INTENT(OUT)       
!    interp_index:    The index array of dimension (2 x KN1) for 
!                     Start index for relevant PZ row array segment and
!                     End index for relevant PZ row array segment, where KN1 = SIZE(PX1) 
!                     UNITS:      N/A                                  
!                     TYPE:       Integer         
!                     DIMENSION:  rank-2
!                     ATTRIBUTES: INTENT(IN)                         
!
!     Comments:
!
!     1) PX1(i)<PX1(i+1) & PX2(i)<PX2(i+1)
!
! RESTRICTIONS:
!     To be efficient, this routine does not check that x and u are both
!     monotonically ascending and the index bounds.
!
!     - Journal reference:
!       Rochon, Y.J., L. Garand, D.S. Turner, and S. Polavarapu.
!       Jacobian mapping between vertical coordinate systems in data assimilation,
!       Q. J. of the Royal Met. Soc., 133, 1547-1558 (2007) DOI: 10.1002/qj.117
!
! CREATION HISTORY:
!       Written by:     Yong Chen, 08-May-2009
!-----------------------------------------------------------------------------------
!--------------------------------------------------------------------------------
  SUBROUTINE LayerAvg( PX1,PX2,PZ,interp_index)
    REAL(fp),     DIMENSION(:),       INTENT(IN)     :: PX1(:)
    REAL(fp),     DIMENSION(:),       INTENT(IN)     :: PX2(:)
    REAL(fp),     DIMENSION(:,:),     INTENT(OUT)    :: PZ(:, :)
    INTEGER,      DIMENSION(:,:),     INTENT(OUT)    :: interp_index

    ! Local variables
    INTEGER  ::  KN1,KN2, ibot,itop,ii,istart,iend, J,IC,ISKIP,KI
    REAL(fp) ::  z1,z2,z3,zw1,zw2,zsum
    REAL(fp) ::  y1,y2,d,d2,w10,w20,dz,dx,dy,dzd,dxd
    
    KN1 = SIZE(PX1)
    KN2 = SIZE(PX2)
    
    istart=1
    iend=kn1
    DO KI=1,KN1
      z2=px1(ki)
!
      if (ki == 1) then 
         z1=2.0*z2-px1(ki+1)
      else
         z1=px1(ki-1)
      endif   
!
      if (ki == kn1) then
         z3=2.0*z2-z1
      else   
         z3=px1(ki+1)
      endif
      if (z3 > px2(kn2)) z3=px2(kn2)
!
      iskip=0
      if (z2 >= px2(kn2)) then
         z3=px2(kn2)
         z2=px2(kn2)
         iskip=1
      endif
  
! --- Determine forward interpolator
!
      pz(1:kn2,ki)=ZERO
      ic=0
      do j=istart,kn2-1
        if (px2(j) > z3) go to 1000
!
        if (px2(j) <= z2 .and. px2(j+1) > z1) then 
          itop=0
          ibot=0
          if (z1 < z3) then
             y1=z1
             if (px2(j) > z1) then
                y1=px2(j)
                itop=1
             endif
             y2=z2
             if (px2(j+1) < z2) then
                y2=px2(j+1)
                ibot=1
             endif
          else
             y1=z2
             if (px2(j) > z2) then
                y1=px2(j)
                itop=1
             endif
             y2=z1
             if (px2(j+1) < z1) then
                y2=px2(j+1)
                ibot=1
             endif
          endif
!
! ---     Set weights for forward interpolator
!
          dy=y2-y1
          dz=z1-z2
          if (abs(dz) < SMALLDIFF) then
             write(6,*) 'SUBLAYER: ERROR: dz is <=0. dz = ',dz
             write(6,*) 'z1,z2,z3 = ',z1,z2,z3
             write(6,*) 'px2(j),px2(j+1)    = ',px2(j),px2(j+1)
             return
          else
             dzd=ONE/dz
          endif
          zw1=(z1-y1)*dzd*dy
          zw2=(z1-y2)*dzd*dy
          w10=zw1
          w20=zw2
          dx=(px2(j+1)-px2(j))
          if (abs(dx) < SMALLDIFF) then
             write(6,*) 'SUBLAYER: ERROR: dx is <=0. dx = ',dx
             write(6,*) 'z1,z2,z3 = ',z1,z2,z3
             write(6,*) 'px2(j),px2(j+1)    = ',px2(j),px2(j+1)
             return
          else
             dxd=ONE/dx
          endif
!
          d=(px2(j+1)-z2)*dxd
          if (z1 < z3 .and. ibot == 0) then
             zw1=zw1+zw2*d
             zw2=zw2*(ONE-d)
          else if (z1 > z3 .and. itop == 0) then
             zw2=zw2+zw1*(ONE-d)
             zw1=zw1*d
          end if
          pz(j,ki)=pz(j,ki)+zw1
          pz(j+1,ki)=pz(j+1,ki)+zw2
          ic=1
        endif
!
        if (px2(j) < z3 .and. px2(j+1) >= z2 .and. iskip == 0) then
          itop=0
          ibot=0
          if (z3 < z1) then
             y1=z3
             if (px2(j) > z3) then
                y1=px2(j)
                itop=1
             endif
             y2=z2
             if (px2(j+1) < z2) then
                y2=px2(j+1)
                ibot=1
             endif
          else
             y1=z2
             if (px2(j) > z2) then
                y1=px2(j)
                itop=1
             endif
             y2=z3
             if (px2(j+1) < z3) then
                y2=px2(j+1)
                ibot=1
             endif
          endif
!
! ---     Set weights for forward interpolator
!
          dy=y2-y1
          dz=z3-z2
          if (abs(dz) < SMALLDIFF) then
             write(6,*) 'SUBLAYER: ERROR: dz is <=0. dz = ',dz
             write(6,*) 'z3,z2,z1 = ',z3,z2,z1
             write(6,*) 'px2(j),px2(j+1)    = ',px2(j),px2(j+1)
             return
          else
             dzd=ONE/dz
          endif
          zw1=(z3-y1)*dzd*dy
          zw2=(z3-y2)*dzd*dy
          w10=zw1
          w20=zw2
          dx=(px2(j+1)-px2(j))
          if (abs(dx) < SMALLDIFF) then
             write(6,*) 'SUBLAYER: ERROR: dx is <=0. dx = ',dx
             write(6,*) 'z3,z2,z1 = ',z3,z2,z1
             write(6,*) 'px2(j),px2(j+1)    = ',px2(j),px2(j+1)
             return
          else
             dxd=ONE/dx
          endif
!
          d=(px2(j+1)-z2)*dxd
          if (z3 < z1 .and. ibot == 0) then
             zw1=zw1+zw2*d
             zw2=zw2*(ONE-d)
          else if (z3 > z1 .and. itop == 0) then
             zw2=zw2+zw1*(ONE-d)
             zw1=zw1*d
          end if
          pz(j,ki)=pz(j,ki)+zw1
          pz(j+1,ki)=pz(j+1,ki)+zw2
          ic=1
        endif
      enddo
      j=kn2
 1000 continue
      if (ic == 0) pz(j,ki)=ONE
!
!     Normalize sum to unity (instead of calculating and dividing by
!     weighting denominator)
!
      do ii=istart,kn2                  
        if(PZ(ii,ki) /= ZERO)then   
          interp_index(1, ki)=ii                 
          exit                          
        endif                           
      enddo                             
      istart=interp_index(1, ki)                 

      interp_index(2,ki)=kn2                      

      do ii=interp_index(1, ki)+1,kn2            
        if(PZ(ii,ki) == ZERO)then   
          interp_index(2,ki)=ii-1                 
          exit                          
        endif                           
      enddo                             
      iend=interp_index(2,ki)                     

      zsum=sum(pz(interp_index(1, ki):interp_index(2,ki),ki))
      pz(interp_index(1,ki):interp_index(2,ki),ki)= &
                 pz(interp_index(1,ki):interp_index(2, ki),ki)/zsum
    ENDDO
  
  
  END SUBROUTINE LayerAvg

 
END MODULE ODPS_AtmAbsorption   
