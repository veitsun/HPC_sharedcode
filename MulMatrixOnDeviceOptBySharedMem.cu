#include "include/CInitialData.h"
#include "include/CPrintMatrix.h"
#include "include/Num.h"
#include "include/common.h"
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <cublas_v2.h>
using namespace std;

template <int BLOCK_DIM>
__global__ void MulMatrixOnDeviceOptBySharedMem(int M, int N, int K,
                                                float alpha, float *A, float *B,
                                                float beta, float *C) {
  int row = blockIdx.y * blockDim.y + threadIdx.y;
  int col = blockIdx.x * blockDim.x + threadIdx.x;
  float temp = 0.0;
  __shared__ float SA[BLOCK_DIM][BLOCK_DIM];
  __shared__ float SB[BLOCK_DIM][BLOCK_DIM];
  int width = (K + BLOCK_DIM - 1) / BLOCK_DIM;

  for (int ph = 0; ph < width; ph++) {
    if (row < M && threadIdx.y + ph * BLOCK_DIM < K) {
      SA[threadIdx.x][threadIdx.y] = A[row * K + threadIdx.y + ph * BLOCK_DIM];
    } else {
      SA[threadIdx.x][threadIdx.y] = 0.0f;
    }
    if (col < N && threadIdx.x + ph * BLOCK_DIM < K) {
      SB[threadIdx.x][threadIdx.y] =
          B[(threadIdx.x + ph * BLOCK_DIM) * N + col];
    } else {
      SB[threadIdx.x][threadIdx.y] = 0.0f;
    }
  }
  __syncthreads();
  for (int s = 0; s < BLOCK_DIM; s++) {
    temp += SA[threadIdx.x][s] * SB[s][threadIdx.y];
  }
  __syncthreads();

  if (row < M && col < N) {
    C[row * N + col] = alpha * temp + beta * C[row * N + col];
  }
}

int main(int argc, char **argv) {
  float *hostA;
  float *hostB;
  float *hostC;
  float *gpuRef;
  float alpha = 1.0;
  float beta = 1.0;

  int elemNum = nx * ny;

  // 给主机上的三个矩阵分配内存
  hostA = (float *)malloc(elemNum * sizeof(float));
  hostB = (float *)malloc(elemNum * sizeof(float));
  hostC = (float *)malloc(elemNum * sizeof(float));
  gpuRef = (float *)malloc(elemNum * sizeof(float));
  // 主机上的三个矩阵初始化数据
  CInitialData cinitialData;
  cinitialData.initialDataABCByFile(hostA, hostB, hostC, nx, ny);
  memset(gpuRef, 0, elemNum * sizeof(float));

  // cout << "测试主机上的三个矩阵是否已经被初始化数据" << endl;
  CPrintMatrix cprintmatrix;
  // cprintmatrix.printMatrixABC(hostA, hostB, hostC, nx, ny);

  // -------------------------------------------------------------------------------------GPU计时

  cudaEvent_t start, stop;
  float time;
  cudaEventCreate(&start);
  cudaEventCreate(&stop);

  // -----------------------------------------------------------------------------------------
  // 使用cuda kernel 来执行矩阵乘法
  dim3 blockDim(BLOCK_DIM_x, BLOCK_DIM_y);
  dim3 gridDim((ny + blockDim.x - 1) / blockDim.x,
               (nx + blockDim.y - 1) / blockDim.y);
  float *deviceA;
  float *deviceB;
  float *deviceC;
  CHECK(cudaMalloc((float **)&deviceA, elemNum * sizeof(float)));
  CHECK(cudaMalloc((float **)&deviceB, elemNum * sizeof(float)));
  CHECK(cudaMalloc((float **)&deviceC, elemNum * sizeof(float)));
  CHECK(cudaMemcpy(deviceA, hostA, elemNum * sizeof(float),
                   cudaMemcpyHostToDevice));
  CHECK(cudaMemcpy(deviceB, hostB, elemNum * sizeof(float),
                   cudaMemcpyHostToDevice));
  CHECK(cudaMemcpy(deviceC, hostC, elemNum * sizeof(float),
                   cudaMemcpyHostToDevice));
  cudaEventRecord(start, 0);
  MulMatrixOnDeviceOptBySharedMem<16><<<gridDim, blockDim>>>(
      nx, nx, nx, alpha, deviceA, deviceB, beta, deviceC);

  cudaEventRecord(stop, 0);
  cudaEventSynchronize(stop);

  cudaEventElapsedTime(&time, start, stop);
  printf("MulMatrixOnDeviceOptBySharedMem Time elapsed %f ms\n", time);
  cudaEventDestroy(start);
  cudaEventDestroy(stop);

  CHECK(cudaMemcpy(gpuRef, deviceC, elemNum * sizeof(float),
                   cudaMemcpyDeviceToHost));
  CHECK(cudaDeviceSynchronize());
  cprintmatrix.printMatrixCinFile(gpuRef, nx, ny);
  // -----------------------------------------------------------------------------------------
  CHECK(cudaFree(deviceA));
  CHECK(cudaFree(deviceB));
  CHECK(cudaFree(deviceC));
  free(hostA);
  free(hostB);
  free(hostC);
  free(gpuRef);

  return 0;
}