!
! Hyperbolic step functions for differentiable replacement of IF statements
!
!
! CREATION HISTORY:
!       Written by:     Paul van Delst, 09-Nov-2010
!                       paul.vandelst@noaa.gov
!

MODULE Hyperbolic_Step

  ! -----------------
  ! Environment setup
  ! -----------------
  ! Module use
  USE Type_Kinds, ONLY: fp
  ! Disable implicit typing
  IMPLICIT NONE


  ! ------------
  ! Visibilities
  ! ------------
  PRIVATE
  PUBLIC :: Step
  PUBLIC :: Step_TL
  PUBLIC :: Step_AD


  ! -----------------
  ! Module parameters
  ! -----------------
  CHARACTER(*), PARAMETER :: MODULE_VERSION_ID = &
  '$Id$'
  ! Literals
  REAL(fp), PARAMETER :: ZERO   = 0.0_fp
  REAL(fp), PARAMETER :: POINT5 = 0.5_fp
  REAL(fp), PARAMETER :: ONE    = 1.0_fp


CONTAINS


!--------------------------------------------------------------------------------
!:sdoc+:
!
! NAME:
!       Step
!
! PURPOSE:
!       Subroutine to compute a hyperbolic, differentiable, step function:
!
!         g(x) = 0.5(1 + TANH(x))
!
! CALLING SEQUENCE:
!       CALL Step( x, g )
!                             
!
! INPUTS:
!       x:      The function abscissa.
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(IN)
!
! OUTPUTS:
!       g:      The hyperbolic step function value.
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(OUT)
!
!:sdoc-:
!--------------------------------------------------------------------------------

  SUBROUTINE Step( x, g )
    REAL(fp), INTENT(IN)  :: x
    REAL(fp), INTENT(OUT) :: g
    g = POINT5 * ( ONE + TANH(x) )
  END SUBROUTINE Step


!--------------------------------------------------------------------------------
!:sdoc+:
!
! NAME:
!       Step_TL
!
! PURPOSE:
!       Subroutine to compute the tangent-linear form of a hyperbolic,
!       differentiable, step function:
!
!         g(x) = 0.5(1 + TANH(x))
!
! CALLING SEQUENCE:
!       CALL Step_TL( x, x_TL, g_TL )
!                             
!
! INPUTS:
!       x:      The function abscissa.
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(IN)
!
!       x_TL:   The tangent-linear abscissa.
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(IN)
!
! OUTPUTS:
!       g_TL:   The tangent-linear hyperbolic step function value.
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(OUT)
!
!:sdoc-:
!--------------------------------------------------------------------------------

  SUBROUTINE Step_TL( x, x_TL, g_TL )
    REAL(fp), INTENT(IN)  :: x, x_TL
    REAL(fp), INTENT(OUT) :: g_TL
    g_TL = POINT5 * x_TL / COSH(x)**2
  END SUBROUTINE Step_TL


!--------------------------------------------------------------------------------
!:sdoc+:
!
! NAME:
!       Step_AD
!
! PURPOSE:
!       Subroutine to compute the adjoint of a hyperbolic, differentiable,
!       step function:
!
!         g(x) = 0.5(1 + TANH(x))
!
! CALLING SEQUENCE:
!       CALL Step_AD( x, g_AD, x_AD )
!                             
!
! INPUTS:
!       x:      The function abscissa.
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(IN)
!
!       g_AD:   The adjoint hyperbolic step function value.
!               NOTE: *** SET TO ZERO UPON EXIT ***
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(IN OUT)
!
! OUTPUTS:
!       x_AD:   The adjoint abscissa.
!               NOTE: *** MUST CONTAIN VALUE UPON ENTRY ***
!               UNITS:      N/A
!               TYPE:       REAL(fp)
!               DIMENSION:  Scalar
!               ATTRIBUTES: INTENT(IN OUT)
!
!:sdoc-:
!--------------------------------------------------------------------------------

  SUBROUTINE Step_AD( x, g_AD, x_AD )
    REAL(fp), INTENT(IN)     :: x
    REAL(fp), INTENT(IN OUT) :: g_AD  ! AD Input
    REAL(fp), INTENT(IN OUT) :: x_AD  ! AD Output
    x_AD = x_AD + POINT5 * g_AD / COSH(x)**2
    g_AD = ZERO
  END SUBROUTINE Step_AD

END MODULE Hyperbolic_Step
