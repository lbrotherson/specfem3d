!=====================================================================
!
!               S p e c f e m 3 D  V e r s i o n  3 . 0
!               ---------------------------------------
!
!     Main historical authors: Dimitri Komatitsch and Jeroen Tromp
!                              CNRS, France
!                       and Princeton University, USA
!                 (there are currently many more authors!)
!                           (c) October 2017
!
! This program is free software; you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by
! the Free Software Foundation; either version 3 of the License, or
! (at your option) any later version.
!
! This program is distributed in the hope that it will be useful,
! but WITHOUT ANY WARRANTY; without even the implied warranty of
! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
! GNU General Public License for more details.
!
! You should have received a copy of the GNU General Public License along
! with this program; if not, write to the Free Software Foundation, Inc.,
! 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
!
!=====================================================================


  subroutine compute_seismograms()

  use specfem_par
  use specfem_par_acoustic
  use specfem_par_elastic
  use specfem_par_poroelastic

  implicit none

  ! local parameters
  real(kind=CUSTOM_REAL),dimension(NDIM,NGLLX,NGLLY,NGLLZ):: displ_element,veloc_element,accel_element
  ! interpolated wavefield values
  double precision :: dxd,dyd,dzd,vxd,vyd,vzd,axd,ayd,azd,pd

  integer :: irec_local,irec
  integer :: iglob,ispec,i,j,k

  ! adjoint locals
  real(kind=CUSTOM_REAL),dimension(NDIM,NDIM):: eps_s
  real(kind=CUSTOM_REAL),dimension(NDIM):: eps_m_s
  real(kind=CUSTOM_REAL):: stf_deltat
  double precision :: stf
  double precision,dimension(NDIM,NDIM) :: rotation_seismo

  do irec_local = 1,nrec_local

    ! initializes wavefield values
    dxd = ZERO
    dyd = ZERO
    dzd = ZERO

    vxd = ZERO
    vyd = ZERO
    vzd = ZERO

    axd = ZERO
    ayd = ZERO
    azd = ZERO

    pd  = ZERO

    ! gets local receiver interpolators
    ! (1-D Lagrange interpolators)
    hxir(:) = hxir_store(irec_local,:)
    hetar(:) = hetar_store(irec_local,:)
    hgammar(:) = hgammar_store(irec_local,:)

    ! gets global number of that receiver
    irec = number_receiver_global(irec_local)

    ! spectral element in which the receiver is located
    if (SIMULATION_TYPE == 2) then
      ! adjoint "receivers" are located at CMT source positions
      ! note: we take here xi_source,.. when FASTER_RECEIVERS_POINTS_ONLY is set
      ispec = ispec_selected_source(irec)
    else
      ! receiver located at station positions
      ispec = ispec_selected_rec(irec)
    endif

    ! calculates interpolated wavefield values at receiver positions
    select case (SIMULATION_TYPE)
    case (1,2)
      ! forward simulations & pure adjoint simulations
      ! wavefields stored in displ,veloc,accel

      ! elastic wave field
      if (ispec_is_elastic(ispec)) then
        ! interpolates displ/veloc/accel at receiver locations
        call compute_interpolated_dva_viscoelast(displ,veloc,accel,NGLOB_AB, &
                                      ispec,NSPEC_AB,ibool, &
                                      hxir,hetar,hgammar, &
                                      dxd,dyd,dzd,vxd,vyd,vzd,axd,ayd,azd)
      endif ! elastic

      ! acoustic wave field
      if (ispec_is_acoustic(ispec)) then
        ! displacement vector
        call compute_gradient_in_acoustic(ispec,NSPEC_AB,NGLOB_AB, &
                        potential_acoustic,displ_element, &
                        hprime_xx,hprime_yy,hprime_zz, &
                        xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                        ibool,rhostore,GRAVITY)

        ! velocity vector
        call compute_gradient_in_acoustic(ispec,NSPEC_AB,NGLOB_AB, &
                        potential_dot_acoustic,veloc_element, &
                        hprime_xx,hprime_yy,hprime_zz, &
                        xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                        ibool,rhostore,GRAVITY)

        ! acceleration vector
        call compute_gradient_in_acoustic(ispec,NSPEC_AB,NGLOB_AB, &
                        potential_dot_dot_acoustic,accel_element, &
                        hprime_xx,hprime_yy,hprime_zz, &
                        xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                        ibool,rhostore,GRAVITY)

        ! interpolates displ/veloc/accel/pressure at receiver locations
        call compute_interpolated_dva_acoust(displ_element,veloc_element,accel_element, &
                                             potential_dot_dot_acoustic,potential_acoustic,NGLOB_AB, &
                                             ispec,NSPEC_AB,ibool, &
                                             hxir,hetar,hgammar, &
                                             dxd,dyd,dzd,vxd,vyd,vzd,axd,ayd,azd,pd,USE_TRICK_FOR_BETTER_PRESSURE)
      endif ! acoustic

      ! poroelastic wave field
      if (ispec_is_poroelastic(ispec)) then
        ! interpolates displ/veloc/accel at receiver locations
        call compute_interpolated_dva_viscoelast(displs_poroelastic,velocs_poroelastic,accels_poroelastic,NGLOB_AB, &
                                      ispec,NSPEC_AB,ibool, &
                                      hxir,hetar,hgammar, &
                                      dxd,dyd,dzd,vxd,vyd,vzd,axd,ayd,azd)
      endif ! poroelastic

    case (3)
      ! adjoint/kernel simulations
      ! reconstructed forward wavefield stored in b_displ, b_veloc, b_accel

      ! elastic wave field
      if (ispec_is_elastic(ispec)) then
        ! backward field: interpolates displ/veloc/accel at receiver locations
        call compute_interpolated_dva_viscoelast(b_displ,b_veloc,b_accel,NGLOB_ADJOINT, &
                                      ispec,NSPEC_AB,ibool, &
                                      hxir,hetar,hgammar, &
                                      dxd,dyd,dzd,vxd,vyd,vzd,axd,ayd,azd)
      endif ! elastic

      ! acoustic wave field
      if (ispec_is_acoustic(ispec)) then
        ! backward field: displacement vector
        call compute_gradient_in_acoustic(ispec,NSPEC_AB,NGLOB_ADJOINT, &
                        b_potential_acoustic,displ_element, &
                        hprime_xx,hprime_yy,hprime_zz, &
                        xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                        ibool,rhostore,GRAVITY)

        ! backward field: velocity vector
        call compute_gradient_in_acoustic(ispec,NSPEC_AB,NGLOB_ADJOINT, &
                        b_potential_dot_acoustic,veloc_element, &
                        hprime_xx,hprime_yy,hprime_zz, &
                        xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                        ibool,rhostore,GRAVITY)

        ! backward field: acceleration vector
        call compute_gradient_in_acoustic(ispec,NSPEC_AB,NGLOB_AB, &
                        b_potential_dot_dot_acoustic,accel_element, &
                        hprime_xx,hprime_yy,hprime_zz, &
                        xix,xiy,xiz,etax,etay,etaz,gammax,gammay,gammaz, &
                        ibool,rhostore,GRAVITY)

        ! backward field: interpolates displ/veloc/accel/pressure at receiver locations
        call compute_interpolated_dva_acoust(displ_element,veloc_element,accel_element, &
                                             b_potential_dot_dot_acoustic,b_potential_acoustic,NGLOB_ADJOINT, &
                                             ispec,NSPEC_AB,ibool, &
                                             hxir,hetar,hgammar, &
                                             dxd,dyd,dzd,vxd,vyd,vzd,axd,ayd,azd,pd,USE_TRICK_FOR_BETTER_PRESSURE)
      endif ! acoustic

    end select ! SIMULATION_TYPE

    ! additional calculations for pure adjoint simulations
    ! computes derivatives of source parameters
    if (SIMULATION_TYPE == 2) then

      ! elastic wave field
      if (ispec_is_elastic(ispec)) then
        ! stores elements displacement field
        do k = 1,NGLLZ
          do j = 1,NGLLY
            do i = 1,NGLLX
              iglob = ibool(i,j,k,ispec)
              displ_element(:,i,j,k) = displ(:,iglob)
            enddo
          enddo
        enddo

        ! gets derivatives of local receiver interpolators
        hpxir(:) = hpxir_store(irec_local,:)
        hpetar(:) = hpetar_store(irec_local,:)
        hpgammar(:) = hpgammar_store(irec_local,:)

        ! computes the integrated derivatives of source parameters (M_jk and X_s)
        call compute_adj_source_frechet(displ_element,Mxx(irec),Myy(irec),Mzz(irec), &
                                        Mxy(irec),Mxz(irec),Myz(irec),eps_s,eps_m_s, &
                                        hxir,hetar,hgammar,hpxir,hpetar,hpgammar, &
                                        hprime_xx,hprime_yy,hprime_zz, &
                                        xix(:,:,:,ispec),xiy(:,:,:,ispec),xiz(:,:,:,ispec), &
                                        etax(:,:,:,ispec),etay(:,:,:,ispec),etaz(:,:,:,ispec), &
                                        gammax(:,:,:,ispec),gammay(:,:,:,ispec),gammaz(:,:,:,ispec))

        stf = comp_source_time_function(dble(NSTEP-it)*DT-t0-tshift_src(irec),hdur_Gaussian(irec))
        stf_deltat = stf * deltat

        Mxx_der(irec_local) = Mxx_der(irec_local) + eps_s(1,1) * stf_deltat
        Myy_der(irec_local) = Myy_der(irec_local) + eps_s(2,2) * stf_deltat
        Mzz_der(irec_local) = Mzz_der(irec_local) + eps_s(3,3) * stf_deltat
        Mxy_der(irec_local) = Mxy_der(irec_local) + 2 * eps_s(1,2) * stf_deltat
        Mxz_der(irec_local) = Mxz_der(irec_local) + 2 * eps_s(1,3) * stf_deltat
        Myz_der(irec_local) = Myz_der(irec_local) + 2 * eps_s(2,3) * stf_deltat

        sloc_der(:,irec_local) = sloc_der(:,irec_local) + eps_m_s(:) * stf_deltat
      endif ! elastic
    endif

    if (SIMULATION_TYPE == 2) then
      ! adjoint simulations
      ! adjoint "receiver" N/E/Z orientations given by nu_source array
      rotation_seismo(:,:) = nu_source(:,:,irec)
    else
      rotation_seismo(:,:) = nu(:,:,irec)
    endif

    ! we only store if needed
    ! note: current index is seismo_current, this allows to store arrays only up to NTSTEP_BETWEEN_OUTPUT_SEISMOS
    !       which could be used to limit the allocation size of these arrays for a large number of receivers
    if (SAVE_SEISMOGRAMS_DISPLACEMENT) &
      seismograms_d(:,irec_local,seismo_current) = real(rotation_seismo(:,1)*dxd + rotation_seismo(:,2)*dyd &
                                                      + rotation_seismo(:,3)*dzd,kind=CUSTOM_REAL)

    if (SAVE_SEISMOGRAMS_VELOCITY) &
      seismograms_v(:,irec_local,seismo_current) = real(rotation_seismo(:,1)*vxd + rotation_seismo(:,2)*vyd &
                                                      + rotation_seismo(:,3)*vzd,kind=CUSTOM_REAL)

    if (SAVE_SEISMOGRAMS_ACCELERATION) &
      seismograms_a(:,irec_local,seismo_current) = real(rotation_seismo(:,1)*axd + rotation_seismo(:,2)*ayd &
                                                      + rotation_seismo(:,3)*azd,kind=CUSTOM_REAL)

    ! only one scalar in the case of pressure
    if (SAVE_SEISMOGRAMS_PRESSURE) seismograms_p(1,irec_local,seismo_current) = real(pd,kind=CUSTOM_REAL)

    ! adjoint simulations
    if (SIMULATION_TYPE == 2) then
      seismograms_eps(:,:,irec_local,it) = eps_s(:,:)
    endif

  enddo ! nrec_local

  end subroutine compute_seismograms
