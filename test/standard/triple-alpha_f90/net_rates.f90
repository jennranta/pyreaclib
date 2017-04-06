module net_rates
  use screening_module, only: screen5, add_screening_factor, screening_init, plasma_state, fill_plasma_state
  use network

  implicit none

  logical, parameter :: screen_reaclib = .true.
  
  ! Temperature coefficient arrays (numbers correspond to reaction numbers in net_info)
  double precision, allocatable :: ctemp_rate(:,:)

  ! Index into ctemp_rate, dimension 2, where each rate's coefficients start  
  integer, dimension(nrat_reaclib) :: rate_start_idx = (/ &
    1, &
    4 /)
  
  ! Reaction multiplicities-1 (how many rates contribute - 1)
  integer, dimension(nrat_reaclib) :: rate_extra_mult = (/ &
    2, &
    2 /)

  ! Should these reactions be screened?
  logical, dimension(nrat_reaclib) :: do_screening = (/ &
    .false., &
    .true. /)

contains

  subroutine init_reaclib()

    allocate( ctemp_rate(7, 6) )
    ! c12_gaa_he4
    ctemp_rate(:, 1) = (/  &
        3.49561000000000d+01, &
        -8.54472000000000d+01, &
        -2.35700000000000d+01, &
        2.04886000000000d+01, &
        -1.29882000000000d+01, &
        -2.00000000000000d+01, &
        8.33330000000000d-01 /)

    ctemp_rate(:, 2) = (/  &
        4.57734000000000d+01, &
        -8.44227000000000d+01, &
        -3.70600000000000d+01, &
        2.93493000000000d+01, &
        -1.15507000000000d+02, &
        -1.00000000000000d+01, &
        1.66667000000000d+00 /)

    ctemp_rate(:, 3) = (/  &
        2.23940000000000d+01, &
        -8.85493000000000d+01, &
        -1.34900000000000d+01, &
        2.14259000000000d+01, &
        -1.34769000000000d+00, &
        8.79816000000000d-02, &
        -1.01653000000000d+01 /)

    ! he4_aag_c12
    ctemp_rate(:, 4) = (/  &
        -9.71052000000000d-01, &
        0.00000000000000d+00, &
        -3.70600000000000d+01, &
        2.93493000000000d+01, &
        -1.15507000000000d+02, &
        -1.00000000000000d+01, &
        -1.33333000000000d+00 /)

    ctemp_rate(:, 5) = (/  &
        -2.43505000000000d+01, &
        -4.12656000000000d+00, &
        -1.34900000000000d+01, &
        2.14259000000000d+01, &
        -1.34769000000000d+00, &
        8.79816000000000d-02, &
        -1.31653000000000d+01 /)

    ctemp_rate(:, 6) = (/  &
        -1.17884000000000d+01, &
        -1.02446000000000d+00, &
        -2.35700000000000d+01, &
        2.04886000000000d+01, &
        -1.29882000000000d+01, &
        -2.00000000000000d+01, &
        -2.16667000000000d+00 /)



  end subroutine init_reaclib

  subroutine term_reaclib()
    deallocate( ctemp_rate )
  end subroutine term_reaclib

  subroutine net_screening_init()
    ! Adds screening factors and calls screening_init

    call add_screening_factor(zion(jhe4), aion(jhe4), &
      zion(jhe4), aion(jhe4))


    call screening_init()    
  end subroutine net_screening_init

  subroutine reaclib_evaluate(pstate, temp, iwhich, reactvec)

    implicit none
    
    type(plasma_state), intent(in) :: pstate
    double precision, intent(in) :: temp
    integer, intent(in) :: iwhich

    double precision, intent(inout) :: reactvec(6)
    ! reactvec(1) = rate     , the reaction rate
    ! reactvec(2) = drate_dt , the Temperature derivative of rate
    ! reactvec(3) = scor     , the screening factor
    ! reactvec(4) = dscor_dt , the Temperature derivative of scor
    ! reactvec(5) = dqweak   , the weak reaction dq-value (ergs)
    !                          (This accounts for modification of the reaction Q
    !                           due to the local density and temperature of the plasma.
    !                           For Reaclib rates, this is 0.0d0.)
    ! reactvec(6) = epart    , the particle energy generation rate (ergs/s)
    ! NOTE: The particle energy generation rate (returned in ergs/s)
    !       is the contribution to enuc from non-ion particles associated
    !       with the reaction.
    !       For example, this accounts for neutrino energy losses
    !       in weak reactions and/or gamma heating of the plasma
    !       from nuclear transitions in daughter nuclei.

    double precision  :: rate, scor ! Rate and Screening Factor
    double precision  :: drate_dt, dscor_dt ! Temperature derivatives
    double precision :: dscor_dd
    double precision :: ri, T9, T9_exp, lnirate, irate, dirate_dt, dlnirate_dt
    integer :: i, j, m, istart

    ri = 0.0d0
    rate = 0.0d0
    drate_dt = 0.0d0
    irate = 0.0d0
    dirate_dt = 0.0d0
    T9 = temp/1.0d9
    T9_exp = 0.0d0
    scor = 1.0d0
    dscor_dt = 0.0d0
    dscor_dd = 0.0d0

    ! Use reaction multiplicities to tell whether the rate is Reaclib
    m = rate_extra_mult(iwhich)

    istart = rate_start_idx(iwhich)

    do i = 0, m
       lnirate = ctemp_rate(1, istart+i) + ctemp_rate(7, istart+i) * LOG(T9)
       dlnirate_dt = ctemp_rate(7, istart+i)/T9
       do j = 2, 6
          T9_exp = (2.0d0*dble(j-1)-5.0d0)/3.0d0 
          lnirate = lnirate + ctemp_rate(j, istart+i) * T9**T9_exp
          dlnirate_dt = dlnirate_dt + &
               T9_exp * ctemp_rate(j, istart+i) * T9**(T9_exp-1.0d0)
       end do
       ! If the rate will be in the approx. interval [0.0, 1.0E-100], replace by 0.0
       ! This avoids issues with passing very large negative values to EXP
       ! and getting results between 0.0 and 1.0E-308, the limit for IEEE 754.
       ! And avoids SIGFPE in CVODE due to tiny rates.
       lnirate = max(lnirate, -230.0d0)
       irate = EXP(lnirate)
       rate = rate + irate
       dirate_dt = irate * dlnirate_dt/1.0d9
       drate_dt = drate_dt + dirate_dt
    end do

    if ( screen_reaclib .and. do_screening(iwhich) ) then
       call screen5(pstate, iwhich, scor, dscor_dt, dscor_dd)
    end if

    reactvec(i_rate)     = rate
    reactvec(i_drate_dt) = drate_dt
    reactvec(i_scor)     = scor
    reactvec(i_dscor_dt) = dscor_dt
    reactvec(i_dqweak)   = 0.0d0
    reactvec(i_epart)    = 0.0d0

    ! write(*,*) '----------------------------------------'
    ! write(*,*) 'IWHICH: ', iwhich
    ! write(*,*) 'reactvec(i_rate)', reactvec(i_rate)
    ! write(*,*) 'reactvec(i_drate_dt)', reactvec(i_drate_dt)
    ! write(*,*) 'reactvec(i_scor)', reactvec(i_scor)    
    ! write(*,*) 'reactvec(i_dscor_dt)', reactvec(i_dscor_dt)
    ! write(*,*) 'reactvec(i_dqweak)', reactvec(i_dqweak)
    ! write(*,*) 'reactvec(i_epart)', reactvec(i_epart)
    ! write(*,*) '----------------------------------------'

  end subroutine reaclib_evaluate
  
end module net_rates
