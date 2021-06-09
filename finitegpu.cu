extern "C" {

#include "ko.h"

}

#include "kogpu.h"

#define TB_SIZE 64
#define ixTEST 13
#define iyTEST 21
#define izTEST 8
#define iiTEST 22222
#define ivTEST 0

ldouble *d_gcov;//[SX*SY*SZMET*sizeof(ldouble)];
ldouble *d_gcon;//[SX*SY*SZMET*sizeof(ldouble)];
ldouble *d_Kris;//[(SX)*(SY)*(SZMET)*64*sizeof(ldouble)];

// copied from get_xb macro in ko.h
__device__ __host__ ldouble get_x_device(ldouble* x_arr, int ic, int idim)
{
  ldouble x_out;
  x_out = (idim==0 ? x_arr[ic+NG] :		     
           (idim==1 ? x_arr[ic+NG + NX+2*NG] :  
	   (idim==2 ? x_arr[ic+NG + NX+2*NG + NY+2*NG ] : 0.)));

  return x_out;
}

// TODO replace get_xb and get_size_x  everywhere
// get grid coordinate on the cell wall indexed ic in dimension idim
// copied from get_xb macro in ko.h
__device__ __host__ ldouble get_xb_device(ldouble* xb_arr, int ic, int idim)
{
  ldouble xb_out;
  xb_out = (idim==0 ? xb_arr[ic+NG] :		     
           (idim==1 ? xb_arr[ic+NG + NX+2*NG + 1] :  
	   (idim==2 ? xb_arr[ic+NG + NX+2*NG +1 + NY+2*NG +1 ] : 0.)));

  return xb_out;
}

__device__ __host__ ldouble get_gKr_device(ldouble* gKr_arr, int i,int j, int k,
				  int ix, int iy, int iz)
{
  ldouble gKr_out = gKr_arr[i*4*4+j*4+k + (iX(ix)+(NGCX))*64 + \
				          (iY(iy)+(NGCY))*(SX)*64 + \
			                  (iZMET(iz)+(NGCZMET))*(SY)*(SX)*64];
  return gKr_out;
}

// get size of cell indexed ic in dimension idim
// copied from get_size_x in finite.c
__device__ __host__ ldouble get_size_x_device(ldouble* xb_arr, int ic, int idim)
{
  ldouble dx;
  dx = get_xb_device(xb_arr, ic+1,idim) - get_xb_device(xb_arr, ic, idim);
  return dx;
}

__device__ __host__ int calc_Tij_device(ldouble *pp, void* ggg, ldouble T[][4])
{
  struct geometry *geom
    = (struct geometry *) ggg;

  //printf("hi from calc_Tij_device\n");
  ldouble (*gg)[5],(*GG)[5];
  gg=geom->gg;
  GG=geom->GG;

  int iv,i,j;
  ldouble rho=pp[RHO];
  ldouble uu=pp[UU];
  ldouble utcon[4],ucon[4],ucov[4];  
  ldouble bcon[4],bcov[4],bsq=0.;
  
  //converts to 4-velocity
  for(iv=1;iv<4;iv++)
    utcon[iv]=pp[1+iv];
  utcon[0]=0.;
  conv_vels_both_device(utcon,ucon,ucov,VELPRIM,VEL4,gg,GG);

#ifdef NONRELMHD
  ucon[0]=1.;
  ucov[0]=-1.;
#endif

#ifdef MAGNFIELD
  calc_bcon_bcov_bsq_from_4vel_device(pp, ucon, ucov, geom, bcon, bcov, &bsq); 
#else
  bcon[0]=bcon[1]=bcon[2]=bcon[3]=0.;
  bsq=0.;
#endif
  
  ldouble gamma=GAMMA;
  #ifdef CONSISTENTGAMMA
  //gamma=pick_gammagas(geom->ix,geom->iy,geom->iz); //TODO
  #endif
  ldouble gammam1=gamma-1.;

  ldouble p=(gamma-1.)*uu; 
  ldouble w=rho+uu+p;
  ldouble eta=w+bsq;
  ldouble ptot=p+0.5*bsq;

#ifndef NONRELMHD  
  for(i=0;i<4;i++)
    for(j=0;j<4;j++)
      T[i][j]=eta*ucon[i]*ucon[j] + ptot*GG[i][j] - bcon[i]*bcon[j];
#else
  
  ldouble v2=dot3nr(ucon,ucov); //TODO
  for(i=1;i<4;i++)
    for(j=1;j<4;j++)
      T[i][j]=(rho)*ucon[i]*ucon[j] + ptot*GG[i][j] - bcon[i]*bcon[j];

  T[0][0]=uu + bsq/2. + rho*v2/2.;
  for(i=1;i<4;i++)
    T[0][i]=T[i][0]=(T[0][0] + ptot) *ucon[i]*ucon[0] + ptot*GG[i][0] - bcon[i]*bcon[0];

#endif  // ifndef NONRELMHD

  return 0;
}



// fill geometry
__device__ __host__ int fill_geometry_device(int ix,int iy,int iz, ldouble* x_arr,void* geom,ldouble* g_arr, ldouble* G_arr)
{
  int i,j;

  struct geometry *ggg 
    = (struct geometry *) geom;

  ggg->par=-1;
  ggg->ifacedim = -1;

  for(i=0;i<4;i++)
  {
    for(j=0;j<5;j++)
    {
      ggg->gg[i][j]=get_g(g_arr,i,j,ix,iy,iz);
      ggg->GG[i][j]=get_g(G_arr,i,j,ix,iy,iz);
    }
  }

  //pick_g(ix,iy,iz,ggg->gg);
  ///pick_G(ix,iy,iz,ggg->GG);
  ggg->alpha=sqrt(-1./ggg->GG[0][0]);
  ggg->ix=ix;  ggg->iy=iy;  ggg->iz=iz;
  ggg->xxvec[0]=0.;
  ggg->xxvec[1]=get_x_device(x_arr, ix,0);
  ggg->xxvec[2]=get_x_device(x_arr, iy,1);
  ggg->xxvec[3]=get_x_device(x_arr, iz,2);
  ggg->xx=ggg->xxvec[1];
  ggg->yy=ggg->xxvec[2];
  ggg->zz=ggg->xxvec[3];
  ggg->gdet=ggg->gg[3][4];
  ggg->gttpert=ggg->GG[3][4];
  ggg->coords=MYCOORDS;
    
  return 0;
  
}


// Metric source term

// TODO: deleted RADIATION and SHEARINGBOX parts
__device__ __host__ int f_metric_source_term_device(int ix, int iy, int iz, ldouble* ss,
		      	                            ldouble* p_arr, ldouble* x_arr,
			                            ldouble* g_arr, ldouble* G_arr, ldouble* gKr_arr)
{
  //int i;

  struct geometry geom;
  fill_geometry_device(ix,iy,iz,x_arr,&geom,g_arr,G_arr);
  //printf("Fill geometry successful.\n");   
    
  //f_metric_source_term_arb(&get_u(p_arr,0,ix,iy,iz), &geom, ss, l_arr); // --> replace with code here, no need for two functions
  //struct geometry *geom = (struct geometry *) ggg;
  
  ldouble (*gg)[5],(*GG)[5],gdetu;
  ldouble *pp = &get_u(p_arr,0,ix,iy,iz);
  
  gg=geom.gg;
  GG=geom.GG;

  #if (GDETIN==0) //no metric determinant inside derivatives
  gdetu=1.;
  #else
  gdetu=geom.gdet;
  #endif

  ldouble dlgdet[3];
  dlgdet[0]=gg[0][4]; //D[gdet,x1]/gdet
  dlgdet[1]=gg[1][4]; //D[gdet,x2]/gdet
  dlgdet[2]=gg[2][4]; //D[gdet,x3]/gdet
  
  ldouble T[4][4];
  int ii, jj;
  //calculating stress energy tensor components
  calc_Tij_device(pp,&geom,T); // TODO
  for(ii=0;ii<4;ii++)
    for(jj=0;jj<4;jj++)
      T[ii][jj]=0.;
  
  indices_2221_device(T,T,gg);


  /*
  for(ii=0;ii<4;ii++)
    for(jj=0;jj<4;jj++)
      {
	if(isnan(T[ii][jj])) 
	  {
	    printf("%d %d %e\n",ii,jj,T[ii][jj]);
	    my_err("nan in metric_source_terms\n");
	  }
      }
  */
  
  //converting to 4-velocity
  ldouble vcon[4],ucon[4];
  vcon[1]=pp[2];
  vcon[2]=pp[3];
  vcon[3]=pp[4];
  
  conv_vels_device(vcon,ucon,VELPRIM,VEL4,gg,GG); //TODO
  //ucon[0]=1.; ucon[1]=0.; ucon[2]=0.; ucon[2]=0.; //TODO 
  
  int k,l,iv;
  for(iv=0;iv<NV;iv++)
    ss[iv]=0.;  // zero out all source terms initially

  //terms with Christoffels
  for(k=0;k<4;k++)
    for(l=0;l<4;l++)
      {
	ss[1]+=gdetu*T[k][l]*get_gKr_device(gKr_arr,l,0,k,ix,iy,iz);
	ss[2]+=gdetu*T[k][l]*get_gKr_device(gKr_arr,l,1,k,ix,iy,iz);
	ss[3]+=gdetu*T[k][l]*get_gKr_device(gKr_arr,l,2,k,ix,iy,iz);
	ss[4]+=gdetu*T[k][l]*get_gKr_device(gKr_arr,l,3,k,ix,iy,iz);
      }

  //terms with dloggdet  
#if (GDETIN==0)
  for(l=1;l<4;l++)
    {
      ss[0]+=-dlgdet[l-1]*pp[RHO]*ucon[l];
      ss[1]+=-dlgdet[l-1]*(T[l][0]+pp[RHO]*ucon[l]);
      ss[2]+=-dlgdet[l-1]*(T[l][1]);
      ss[3]+=-dlgdet[l-1]*(T[l][2]);
      ss[4]+=-dlgdet[l-1]*(T[l][3]);
      ss[5]+=-dlgdet[l-1]*pp[ENTR]*ucon[l];
    }   
#endif
  
  return 0;
}

__global__ void calc_update_gpu_kernel(ldouble dtin, int Nloop_0, 
                                       int* loop_0_ix, int* loop_0_iy, int* loop_0_iz,
				       ldouble* x_arr, ldouble* xb_arr,
				       ldouble* flbx_arr, ldouble* flby_arr, ldouble* flbz_arr,
				       ldouble* u_arr, ldouble* p_arr, ldouble* d_gcov, ldouble* d_gcon, ldouble* d_Kris)

{

  int ii;
  int ix,iy,iz,iv;
  ldouble dx,dy,dz;
  ldouble flxl,flxr,flyl,flyr,flzl,flzr;
  ldouble val,du;
  ldouble ms[NV];
  //ldouble gs[NV]; //NOTE gs[NV] is for artifical sources, rarely used

  // get index for this thread
  // Nloop_0 is number of cells to update;
  // usually Nloop_0=NX*NY*NZ, but sometimes there are weird bcs inside domain 
  ii = blockIdx.x * blockDim.x + threadIdx.x;
  if(ii >= Nloop_0) return;
    
  // get indices from 1D arrays
  ix=loop_0_ix[ii];
  iy=loop_0_iy[ii];
  iz=loop_0_iz[ii]; 

  if(ii==iiTEST){
    printf("D   : %d %d %d %d\n",ii, ix,iy,iz);
  }

  // Source term
  // check if cell is active
  // NOTE: is_cell_active always returns 1 -- a placeholder function put in long ago
  
  if(0) //if(is_cell_active(ix,iy,iz)==0)
  {
    // Source terms applied only for active cells	  
    for(iv=0;iv<NV;iv++) ms[iv]=0.; 
  }
  else
  {
     // Get metric source terms ms[iv]
     // and any other source terms gs[iv] 

     f_metric_source_term_device(ix,iy,iz,ms,p_arr, x_arr,d_gcov,d_gcon,d_Kris);  //TODO: somewhat complicated

     //f_general_source_term(ix,iy,iz,gs); //NOTE: *very* rarely used, ignore for now
     for(iv=0;iv<NV;iv++)
     {
       ms[iv] = 0; // TODO: placeholder metric term of 0
       //ms[iv]+=gs[iv];
     }
  }
    
  // Get the cell size in the three directions
  dx = get_size_x_device(xb_arr,ix,0); //dx=get_size_x(ix,0);
  dy = get_size_x_device(xb_arr,iy,1); //dy=get_size_x(iy,1);
  dz = get_size_x_device(xb_arr,iz,2); //dz=get_size_x(iz,2);

  // test sizes 
  if(ii==iiTEST)
  {
    printf("D size_x 0 %e \n", get_size_x_device(xb_arr,ixTEST,0));
    printf("D size_x 1 %e \n", get_size_x_device(xb_arr,iyTEST,1));
    printf("D size_x 2 %e \n", get_size_x_device(xb_arr,izTEST,2));
  }
  
  //update all conserved according to fluxes and source terms      
  for(iv=0;iv<NV;iv++)
  {	

    // Get the initial value of the conserved quantity
    val = get_u(u_arr,iv,ix,iy,iz);
    
    if(ix==ixTEST && iy==iyTEST && iz==izTEST && iv==ivTEST)
      printf("D u: %e\n", val);
    
    // Get the fluxes on the six faces.
    // flbx, flby, flbz are the fluxes at the LEFT walls of cell ix, iy, iz.
    // To get the RIGHT fluxes, we need flbx(ix+1,iy,iz), etc.
    flxl=get_ub(flbx_arr,iv,ix,iy,iz,0);
    flxr=get_ub(flbx_arr,iv,ix+1,iy,iz,0);
    flyl=get_ub(flby_arr,iv,ix,iy,iz,1);
    flyr=get_ub(flby_arr,iv,ix,iy+1,iz,1);
    flzl=get_ub(flbz_arr,iv,ix,iy,iz,2);
    flzr=get_ub(flbz_arr,iv,ix,iy,iz+1,2);

    
    if(ix==ixTEST && iy==iyTEST && iz==izTEST && iv==ivTEST)
      printf("D fluxes: %e %e %e %e %e %e\n", flxl,flxr,flyl,flyr,flzl,flzr);

    // Compute Delta U from the six fluxes
    du = -(flxr-flxl)*dtin/dx - (flyr-flyl)*dtin/dy - (flzr-flzl)*dtin/dz;

    // Compute the new conserved by adding Delta U and the source term
    val += (du + ms[iv]*dtin);

    // Save the new conserved to memory
    
//#ifdef SKIPHDEVOLUTION
//  if(iv>=NVMHD)
//#endif
//#ifdef RADIATION
//#ifdef SKIPRADEVOLUTION
//#ifdef EVOLVEPHOTONNUMBER
//  if(iv!=EE && iv!=FX && iv!=FY && iv!=FZ && iv!=NF)
//#else
//  if(iv!=EE && iv!=FX && iv!=FY && iv!=FZ)
//#endif
//#endif  
//#endif  
//#ifdef SKIPHDBUTENERGY
//  if(iv>=NVMHD || iv==UU)
//#endif
	
    u_arr[iv] = val;
    //set_u(u,iv,ix,iy,iz,val);	 

  }  
}

int calc_update_gpu(ldouble dtin)
{

  int *d_loop0_ix,*d_loop0_iy,*d_loop0_iz;
  int *h_loop0_ix,*h_loop0_iy,*h_loop0_iz;
  ldouble *d_x_arr;
  ldouble *d_xb_arr;
  ldouble *d_u_arr, *d_p_arr;
  //ldouble *d_g_arr, *d_G_arr, *d_gKr_arr;
  ldouble *d_flbx_arr,*d_flby_arr,*d_flbz_arr;
  
  cudaError_t err = cudaSuccess;
  cudaEvent_t start, stop;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);
  // Allocate device arrays 
  
  // printf("ERROR (error code %s)!\n", cudaGetErrorString(err));

  err = cudaMalloc(&d_loop0_ix, sizeof(int)*Nloop_0);
  err = cudaMalloc(&d_loop0_iy, sizeof(int)*Nloop_0);
  err = cudaMalloc(&d_loop0_iz, sizeof(int)*Nloop_0);

  // NOTE: size of xb,flbx,flby,flbz is copied from initial malloc in misc.c
  // these need to be long long if the grid is on one tile and large (~256^3)
  long long Nx    = (NX+NY+NZ+6*NG);
  long long Nxb    = (NX+1+NY+1+NZ+1+6*NG);
  long long Nprim  = (SX)*(SY)*(SZ)*NV;
  long long NfluxX = (SX+1)*(SY)*(SZ)*NV;
  long long NfluxY = (SX)*(SY+1)*(SZ)*NV;
  long long NfluxZ = (SX)*(SY)*(SZ+1)*NV;
  long long Nmet   = (SX)*(SY)*(SZMET)*gSIZE;
  long long Nkris=(SX)*(SY)*(SZMET)*64;
  
  err = cudaMalloc(&d_x_arr,   sizeof(ldouble)*Nx);
  err = cudaMalloc(&d_xb_arr,   sizeof(ldouble)*Nxb);
  err = cudaMalloc(&d_p_arr,    sizeof(ldouble)*Nprim);
  err = cudaMalloc(&d_u_arr,    sizeof(ldouble)*Nprim);
  err = cudaMalloc(&d_flbx_arr, sizeof(ldouble)*NfluxX);
  err = cudaMalloc(&d_flby_arr, sizeof(ldouble)*NfluxY);
  err = cudaMalloc(&d_flbz_arr, sizeof(ldouble)*NfluxZ);
  
  //err = cudaMalloc(&d_g_arr,    sizeof(ldouble)*Nmet);
  //err = cudaMalloc(&d_G_arr,    sizeof(ldouble)*Nmet);
  //err = cudaMalloc(&d_gKr_arr,  sizeof(ldouble)*Nkris);
  
  // Copy data to device arrays
  
  // NOTE: when we add more functions to device, most of these should only be copied once
  // Make 1D arrays of ix,iy,iz indicies and copy to device
  h_loop0_ix = (int*)malloc(sizeof(int)*Nloop_0);
  h_loop0_iy = (int*)malloc(sizeof(int)*Nloop_0);
  h_loop0_iz = (int*)malloc(sizeof(int)*Nloop_0);

  for(int ii=0; ii<Nloop_0; ii++){
    h_loop0_ix[ii] = loop_0[ii][0];     
    h_loop0_iy[ii] = loop_0[ii][1];     
    h_loop0_iz[ii] = loop_0[ii][2];
    if (ii==iiTEST) printf("H   :  %d %d %d %d\n",ii,h_loop0_ix[ii],h_loop0_iy[ii],h_loop0_iz[ii]) ;
  }

  err =  cudaMemcpy(d_loop0_ix, h_loop0_ix, sizeof(int)*Nloop_0, cudaMemcpyHostToDevice);
  err =  cudaMemcpy(d_loop0_iy, h_loop0_iy, sizeof(int)*Nloop_0, cudaMemcpyHostToDevice);
  err =  cudaMemcpy(d_loop0_iz, h_loop0_iz, sizeof(int)*Nloop_0, cudaMemcpyHostToDevice);

  free(h_loop0_ix);
  free(h_loop0_iy);
  free(h_loop0_iz);

  // copy grid boundary data from xb (global array) to device
  printf("H size_x 0 %e \n", get_size_x(ixTEST,0));
  printf("H size_x 1 %e \n", get_size_x(iyTEST,1));
  printf("H size_x 2 %e \n", get_size_x(izTEST,2));
  err =  cudaMemcpy(d_x_arr, x, sizeof(ldouble)*Nx, cudaMemcpyHostToDevice);
  err =  cudaMemcpy(d_xb_arr, xb, sizeof(ldouble)*Nxb, cudaMemcpyHostToDevice);

  // copy conserved quantities from u (global array) to device
  printf("H u: %e \n", get_u(u,ivTEST,ixTEST,iyTEST,izTEST));
  err = cudaMemcpy(d_u_arr, u, sizeof(ldouble)*Nprim, cudaMemcpyHostToDevice);
  err = cudaMemcpy(d_p_arr, p, sizeof(ldouble)*Nprim, cudaMemcpyHostToDevice);

  // copy metric and Christoffels
  //err = cudaMemcpy(d_g_arr, g, sizeof(ldouble)*Nmet, cudaMemcpyHostToDevice);
  //err = cudaMemcpy(d_G_arr, G, sizeof(ldouble)*Nmet, cudaMemcpyHostToDevice);
  //err = cudaMemcpy(d_gKr_arr, gKr, sizeof(ldouble)*Nkris, cudaMemcpyHostToDevice);
  
  // copy fluxes data from flbx,flby,flbz (global arrays) to device
  printf("H fluxes: %e %e %e %e %e %e\n",
	 get_ub(flbx,ivTEST,ixTEST,iyTEST,izTEST,0),
	 get_ub(flbx,ivTEST,ixTEST+1,iyTEST,izTEST,0),
         get_ub(flby,ivTEST,ixTEST,iyTEST,izTEST,1),
	 get_ub(flby,ivTEST,ixTEST,iyTEST+1,izTEST,1),
	 get_ub(flbz,ivTEST,ixTEST,iyTEST,izTEST,2),
	 get_ub(flbz,ivTEST,ixTEST,iyTEST,izTEST+1,2));
  err =  cudaMemcpy(d_flbx_arr, flbx, sizeof(ldouble)*NfluxX, cudaMemcpyHostToDevice);
  err =  cudaMemcpy(d_flby_arr, flby, sizeof(ldouble)*NfluxY, cudaMemcpyHostToDevice);
  err =  cudaMemcpy(d_flbz_arr, flbz, sizeof(ldouble)*NfluxZ, cudaMemcpyHostToDevice);

  // Launch calc_update_gpu_kernel

  int threadblocks = (Nloop_0 / TB_SIZE) + ((Nloop_0 % TB_SIZE)? 1:0);
  printf("\nTest %d\n", threadblocks); fflush(stdout);

  cudaEventRecord(start);
  calc_update_gpu_kernel<<<threadblocks, TB_SIZE>>>(dtin, Nloop_0, 
						    d_loop0_ix, d_loop0_iy, d_loop0_iz,
						    d_x_arr,d_xb_arr,
						    d_flbx_arr, d_flby_arr, d_flbz_arr,
						    d_u_arr, d_p_arr, d_gcov, d_gcon, d_Kris);
  
  cudaEventRecord(stop);
  err = cudaPeekAtLastError();
  cudaDeviceSynchronize(); //TODO: do we need this, does cudaMemcpy synchrotnize?
  
  // printf("ERROR-Kernel (error code %s)!\n", cudaGetErrorString(err));

  cudaEventSynchronize(stop);
  float tms = 0.;
  cudaEventElapsedTime(&tms, start,stop);
  printf("gpu update time: %0.2f \n",tms);
  
  // TODO Copy updated u back from device to global array u?
  //ldouble *u_tmp;
  //err = cudaMemcpy(&u_tmp, d_u_arr, sizeof(ldouble)*Nprim, cudaMemcpyDeviceToHost);
  
  // Free Device Memory
  cudaFree(d_loop0_ix);
  cudaFree(d_loop0_iy);
  cudaFree(d_loop0_iz);
  
  cudaFree(d_x_arr);
  cudaFree(d_xb_arr);
  cudaFree(d_flbx_arr);
  cudaFree(d_flby_arr);
  cudaFree(d_flbz_arr);
  cudaFree(d_u_arr);
  cudaFree(d_p_arr);
  //cudaFree(d_g_arr);
  //cudaFree(d_G_arr);
  //cudaFree(d_gKr_arr);

  // set global timestep dt
  dt = dtin;

  return 0;
}

int push_geometry()
{
  cudaError_t err = cudaSuccess;

  err = cudaMalloc(&d_gcov,   sizeof(ldouble)*SX*SY*SZMET*gSIZE);
  err = cudaMalloc(&d_gcon,   sizeof(ldouble)*SX*SY*SZMET*gSIZE);
  err = cudaMalloc(&d_Kris,    sizeof(ldouble)*SX*SY*SZMET*64);

  err = cudaMemcpy(d_gcov, g, sizeof(double)*SX*SY*SZMET*gSIZE, cudaMemcpyHostToDevice);
  if(err != cudaSuccess) printf("Passing g to device failed.\n"); 
  err = cudaMemcpy(d_gcon, G, sizeof(double)*SX*SY*SZMET*gSIZE, cudaMemcpyHostToDevice);
  if(err != cudaSuccess) printf("Passing G to device failed.\n"); 
  err = cudaMemcpy(d_Kris, gKr, sizeof(double)*(SX)*(SY)*(SZMET)*64, cudaMemcpyHostToDevice);
  if(err != cudaSuccess) printf("Passing gKr to device failed.\n"); 
  
  return 0;
}

int free_geometry()
{
  cudaFree(d_gcov);
  cudaFree(d_gcon);
  cudaFree(d_Kris);

  return 0;
}
