/* 
 *
 * Docs
 * 
 */

#include <cuda.h>
#include <stdlib.h>
#include <stdio.h>
#include <time.h> 
#include <float.h>
#include <math.h>

/* To index element (i,j) of a 2D array stored as 1D */
#define index(i, j, N)  ((i)*(N)) + (j)

/* Config params */
#define PRINT_LOG 1
#define PRINT_ANALYSIS 1
/* Define constants */
#define RANGE 100

/**************************** Definitions *************************************/

// Function declarations
void  seq_clustering(float *, unsigned int, unsigned int, int *, float *);
void  gpu_clustering(float *, unsigned int, unsigned int, int*, float *);
void calculate_pairwise_dists(float *, int, int, float *);
void find_pairwise_min(float *, int, float *, int *);
void merge_clusters(int *, int, int, int);
float calculate_dist(float *, int, int, int);
void print_float_matrix(float *, int, int);
void print_int_matrix(int *, int, int);
int get_parent(int, int *);

// Kernel functions
__global__ void calculate_pairwise_dists_cuda(float *, float *, unsigned int, unsigned int);
__global__ void find_pairwise_min_cuda(float * dist_matrix_d, int n, float* entry, int * indices, float* values);
__global__ void min_reduction(float *, float*, int);
__global__ void remove_cluster(float * dist_matrix_d, int right_cluster, int n);
__global__ void update_cluster(float * dist_matrix_d, int left_cluster, int right_cluster, int n);

/*************************** Helper Functions **************************************/
void print_float_matrix(float * a, int n, int m){
  for(int i=0; i<n; i++){
    for(int j=0; j<m; j++)
      printf("%f ", a[index(i, j, m)]);
    printf("\n");
  }
}

void print_int_matrix(int * a, int n, int m){
  for (int i=0; i<n; i++){
    for(int j=0; j<m; j++)
      printf("%d ", a[index(i,j,m)]);
    printf("\n");
  }
}

void load_data(float * dataset, int n, int m) {
  srand((unsigned int) 0);
  for (int i = 0; i < n; i ++) {
    for (int j = 0; j < m; j++) {
      // assign numbers between 0 and RANGE
      dataset[index(i, j, m)] = ((float)rand()/(float)(RAND_MAX)) * RANGE - RANGE/2.0;
    } 
  }
  if (PRINT_LOG){
    printf("Dataset:\n");
    print_float_matrix(dataset, n, m);
  }
}

void load_test_data(float * dataset) {
  float arr[6][2] = {
    {0.0,0.0},
    {1.0,1.0},
    {10.0,10.0},
    {11.0,11.0},
    {-100.0,-100.0},
    {-111.0,111.0}};

  int n = 6;
  int m = 2;

  for (int i = 0; i < n; i ++) {
    for (int j = 0; j < m; j++) {
      dataset[index(i, j, m)] = arr[i][j];
    } 
  }

  if (PRINT_LOG){
    printf("Dataset:\n");
    print_float_matrix(dataset, n, m);
  }
}


/**************************** main() *************************************/
int main(int argc, char * argv[])
{
  //Define variables
  //unsigned int N; /* Dimention of NxN matrix */
  int type_of_device = atoi(argv[3]); // CPU or GPU
  int n = atoi(argv[1]);
  int m = atoi(argv[2]);

  printf("Hierarchical Clustering:\n");
  printf("Dataset size: %d x %d\n", n, m);
  printf("Device Type: %d\n", type_of_device);
  
  // to measure time taken by a specific part of the code 
  double time_taken;
  clock_t start, end;
  
  // Validate
  /*if(argc != 4)
  {
    fprintf(stderr, "usage: heatdist num  iterations  who\n");
    fprintf(stderr, "num = dimension of the square matrix (50 and up)\n");
    fprintf(stderr, "iterations = number of iterations till stopping (1 and up)\n");
    fprintf(stderr, "who = 0: sequential code on CPU, 1: GPU execution\n");
    exit(1);
  }*/

  //Load data
  float * dataset;
  dataset = (float *)calloc(n*m, sizeof(float));
  if( !dataset )
  {
   fprintf(stderr, " Cannot allocate the %u x %u array\n", n, m);
   exit(1);
  }
  load_data(dataset, n, m);
  //load_test_data(dataset);
  printf("Data loaded!\n");
  
  type_of_device = atoi(argv[3]);

  float dendrogram[(n-1)*3];
  int * result;
  result = (int *)calloc(n, sizeof(int));
  if( type_of_device == 0 ) { 
    // The CPU sequential version 
    start = clock();
    seq_clustering(dataset, n, m, result, dendrogram);    
    end = clock();
  } else {
    // The GPU version
     start = clock();
     gpu_clustering(dataset, n, m, result, dendrogram);
     end = clock();    
  }
  
  
  time_taken = ((double)(end - start))/ CLOCKS_PER_SEC;
  
  printf("Time taken for %s is %lf\n", type_of_device == 0? "CPU" : "GPU", time_taken);

  free(dataset);
  free(result);

  return 0;

}


/*****************  The CPU sequential version **************/
void  seq_clustering(float * dataset, unsigned int n, unsigned int m, int* result, float * dendrogram)
{
  // to measure time taken by a specific part of the code 
  double time_taken;
  clock_t start, end;
  
  if( !result ) {
   fprintf(stderr, " Cannot allocate result %u array\n", n);
   exit(1);
  }

  for (int i = 0; i < n; i++) result[i] = i;

  float* dist_matrix = (float *)calloc(n*n, sizeof(float));
  if( !dist_matrix ) {
   fprintf(stderr, " Cannot allocate dist_matrix %u array\n", n*n);
   exit(1);
  }

  // O(n*n*m) -> GPU
  start = clock();
  calculate_pairwise_dists(dataset, n, m, dist_matrix);
  if (PRINT_LOG)
    print_float_matrix(dist_matrix, n, n);
  end = clock();

  time_taken = ((double)(end - start))/ CLOCKS_PER_SEC;
  if (PRINT_ANALYSIS)
    printf("Time taken for distance computation: %lf\n", time_taken);
  
  start = clock();
  for (int iteration=0; iteration < n - 1; iteration++) {
    
    float entry[3]; 
    // O(I*n*n) -> GPU
    
    find_pairwise_min(dist_matrix, n, entry, result);
    
    
    dendrogram[index(iteration, 0, 3)] = entry[0];
    dendrogram[index(iteration, 1, 3)] = entry[1];
    dendrogram[index(iteration, 2, 3)] = entry[2];
    // O(I*n) -> amortized O(I)
    
    merge_clusters(result, (int)entry[0], (int)entry[1], n);
    
    
    if (PRINT_LOG){
      printf("Iteartion #%d\n", iteration);
      printf("Min Indices: %d, %d\n", (int)entry[0], (int)entry[1]);
      print_int_matrix(result, 1, n);
    }
    
  }

  end = clock();
  time_taken = ((double)(end - start))/ CLOCKS_PER_SEC;
  if (PRINT_ANALYSIS)
      printf("Time taken for merge cluster, Iteration %lf\n",time_taken);
    
  for (int i=0; i<n; i++) result[i] = get_parent(i, result);

  if (PRINT_LOG){
    printf("Cluster IDs:\n");
    print_int_matrix(result, 1, n);
    printf("Dendrogram:\n");
    print_float_matrix(dendrogram, n-1, 3);
  }

  free(dist_matrix);
}

void calculate_pairwise_dists(float * dataset, int n, int m, float * dist_matrix) {
  // O(n)
  // for (int i = 0; i < n*n; i++) dist_matrix[i] = FLT_MAX;
  
  // O(n*n*m)
  for (int i = 0; i < n; i++) {
    for (int j = i+1; j < n; j++) {
      // O(m)
      dist_matrix[index(i, j, n)] = calculate_dist(dataset, i, j, m);
    }
  }  
}

// passing vec1_i and vec2_i instead of float * as dist_matrix is 1-D
float calculate_dist(float * dataset, int i, int j, int dim) {
  float dist = 0;
  // O(m)
  for (int mi = 0; mi < dim; mi++) {
    float x = (dataset[index(i, mi, dim)] - dataset[index(j,mi,dim)]);
    dist += x * x;
  }
  return dist;
}


int get_parent(int curr_parent, int* parents) {
  if (parents[curr_parent] == curr_parent) return curr_parent;
  parents[curr_parent] = get_parent(parents[curr_parent], parents);
  return parents[curr_parent];
  // return get_parent(parents[curr_parent], parents);
}


void find_pairwise_min(float * dist_matrix, int n, float* entry, int* parents) {
  entry[0] = 0;
  entry[1] = 0;
  entry[2] = FLT_MAX;
  for (int i = 0; i < n; i++) {
    for (int j = i+1; j < n; j++) {
      if (get_parent(i, parents) != get_parent(j, parents)) {
      // if (parents[i] != parents[j]) {
        float curr_dist = dist_matrix[index(i, j, n)];
        if (curr_dist < entry[2]) {
          entry[0] = i;
          entry[1] = j;
          entry[2] = curr_dist;
        }
      }
    }
  }
}


void merge_clusters(int * result, int data_point_i, int data_point_j, int dim) {
  if (!(data_point_i >= 0 && data_point_i < dim && data_point_j >= 0 && data_point_j < dim)) {
    printf("merge_clusters out of bounds");
    return;
  } 
  // int cluster_j = result[data_point_j];
  // for(int i=0; i<dim; i++)
  //   if(result[i] == cluster_j)
  //     result[i] = result[data_point_i];
  int parent_i = get_parent(data_point_i, result);
  result[get_parent(data_point_j, result)] = parent_i;
} 

/***************** The GPU version *********************/
/* This function can call one or more kernels if you want ********************/
void gpu_clustering(float * dataset, unsigned int n, unsigned int m, int * result, float * dendrogram){
  double time_taken;
  clock_t start, end;
  // int num_bytes = n*n*sizeof(float);
  for (int i = 0; i < n; i++) result[i] = i;

  // FIXME: Why we have dist_matrix in main memory? do we need it?
  float* dist_matrix = (float *)calloc(n*n, sizeof(float));
  if( !dist_matrix ) {
   fprintf(stderr, " Cannot allocate dist_matrix %u array\n", n*n);
   exit(1);
  }

  float * dist_matrix_d;
  cudaMalloc((void**) &dist_matrix_d, n*n*sizeof(float));
  if (!dist_matrix_d) {
    fprintf(stderr, " Cannot allocate cuda dist_matrix %u array\n", n*n);
    exit(1);
  }

  float * dataset_d;
  cudaMalloc((void**) &dataset_d, n*m*sizeof(float));
  if (!dataset_d) {
    fprintf(stderr, " Cannot allocate cuda dataset %u array\n", n*n);
    exit(1);
  }

  cudaMemcpy(dist_matrix_d, dist_matrix, n*n*sizeof(float), cudaMemcpyHostToDevice);
  cudaMemcpy(dataset_d, dataset, n*m*sizeof(float), cudaMemcpyHostToDevice);

  // Maximum number of threads per block in cuda1.cims.nyu.edu 
  int thread_cnt = 1024;
  int block_cnt = (int) ceil((float)n*n / thread_cnt);
  printf("Launching kernel with %d blocks and %d threads\n", block_cnt, thread_cnt);

  // O(1)
  start = clock();
  calculate_pairwise_dists_cuda<<<block_cnt, thread_cnt>>>(dataset_d, dist_matrix_d, n, m);
  cudaDeviceSynchronize();
  cudaMemcpy(dist_matrix, dist_matrix_d, n*n*sizeof(float), cudaMemcpyDeviceToHost);
  if (PRINT_LOG) {
    printf("Dist Matrix:\n");
    print_float_matrix(dist_matrix, n, n);
  }
  end = clock();

  time_taken = ((double)(end - start))/ CLOCKS_PER_SEC;
  if (PRINT_ANALYSIS)
    printf("Time taken for distance computation: %lf\n", time_taken);
  
  start = clock();

  // Needs to be in shared memory
  int * indices;
  cudaMalloc((void**) &indices, n*n*sizeof(int));
  float * values;
  cudaMalloc((void**) &values, n*n*sizeof(float));

  // O(n)
  for (int iteration=0; iteration < n - 1; iteration++) {
    float entry[3]; 

    // O(log n)
    find_pairwise_min_cuda<<<block_cnt, thread_cnt>>> (dist_matrix_d, n, entry, indices, values);
    cudaDeviceSynchronize();

    // Merge right cluster to left
    dendrogram[index(iteration, 0, 3)] = entry[0];
    dendrogram[index(iteration, 1, 3)] = entry[1];
    dendrogram[index(iteration, 2, 3)] = entry[2];

    // O(1)
    // Update left cluster's distance with all others
    update_cluster<<<block_cnt, thread_cnt>>> (dist_matrix_d, (int)entry[0], (int)entry[1], n);
    cudaDeviceSynchronize();

    // Remove right clusters from further consideration
    remove_cluster<<<block_cnt, thread_cnt>>>(dist_matrix_d, (int)entry[1], n);
    cudaDeviceSynchronize();
  
    if (PRINT_LOG){
      printf("Iteartion #%d\n", iteration);
      printf("Min Indices: %d, %d\n", (int)entry[0], (int)entry[1]);
      // print_int_matrix(result, 1, n);
    }
  }

  cudaMemcpy(dist_matrix, dist_matrix_d, n*n*sizeof(float), cudaMemcpyDeviceToHost);
  if (PRINT_LOG) {
    printf("Dist Matrix:\n");
    print_float_matrix(dist_matrix, n, n);
  }

  end = clock();
  time_taken = ((double)(end - start))/ CLOCKS_PER_SEC;
  if (PRINT_ANALYSIS)
    printf("Time taken for merge cluster %lf\n", time_taken);
    
   if (PRINT_LOG){
  //  printf("Cluster IDs:\n");
  //   print_int_matrix(result, 1, n);
     printf("Dendrogram:\n");
     print_float_matrix(dendrogram, n-1, 3);
   }

  free(dist_matrix);
  cudaFree(dataset_d);
  cudaFree(dist_matrix_d);
}

/*
  Right is being merged to left
  So remove all distance entries for right with any other cluster 
*/ 
__global__ void update_cluster(float * dist_matrix_d, int left_cluster, int right_cluster, int n) {

  int index = threadIdx.x + blockIdx.x * blockDim.x;
  if (index >= n) return;

  int i = index/n;
  int j = index%n;
  if (i == left_cluster) {
    float new_min = min(dist_matrix_d[index(i, j, n)], dist_matrix_d[index(right_cluster, j, n)]);
    dist_matrix_d[index(i, j, n)] = new_min;
  } else if (j == left_cluster) {
    float new_min = min(dist_matrix_d[index(i, j, n)], dist_matrix_d[index(i, right_cluster, n)]);
    dist_matrix_d[index(i, j, n)] = new_min;
  }

  __syncthreads();
}

/*
  Right is being merged to left
  So remove all distance entries for right with any other cluster 
*/ 
__global__ void remove_cluster(float * dist_matrix_d, int right_cluster, int n) {

  int index = threadIdx.x + blockIdx.x * blockDim.x;
  if (index >= n) return;

  int i = index/n;
  int j = index%n;
  if (i == right_cluster || j == right_cluster) {
    dist_matrix_d[index] = FLT_MAX;
  }

  __syncthreads();
}

__global__ void calculate_pairwise_dists_cuda(float * dataset, float * dist_matrix, unsigned int n, unsigned int m)
{
  int index = threadIdx.x + blockDim.x * blockIdx.x;
  // Dont update if thread id is outside of the box
  if (index < n*n){
    int i = index / n;
    int j = index % n;
    if (i<n && j < n) {
      if (i == j) dist_matrix[index(i, j, n)] = FLT_MAX;
      else {
        float dist = 0;
        for(int mi=0; mi<m; mi++){
          float x = (dataset[index(i, mi, m)] - dataset[index(j,mi,m)]);
          dist += x * x;
        }
        dist_matrix[index(i, j, n)] = dist;
      }
    }
  }
}

__global__ void find_pairwise_min_cuda(float * dist_matrix_d, int n, float* entry, int * indices, float* values) {
  entry[0] = 0;
  entry[1] = 0;
  entry[2] = FLT_MAX;

  int index = threadIdx.x + blockIdx.x * blockDim.x;

  // indices and values needs to be shared
  // extern __shared__ int indices[];
  // extern __shared__ float values[];
  for (int stride = n*n/2; stride > 0; stride /= 2) {
    __syncthreads();
    if (index < stride) {
      int left_idx = (stride == n*n/2) ? index : indices[index];
      int right_idx = (stride == n*n/2) ? index + stride : indices[index+stride];

      float left_val = dist_matrix_d[left_idx];
      // We can be outside of boundary in first iteration, handle it gracefully
      float right_val = FLT_MAX;
      if (right_idx < n*n) {
        right_val = dist_matrix_d[right_idx];
      }

      printf("find_pairwise_min_cuda - left_idx %d, left_val %.2f and right_idx %d, right_val %.2f | index %d, stride %d, n %d\n", 
      left_idx, left_val, right_idx, right_val, index, stride, n);

      if (left_val <= right_val) {
        indices[left_idx] = left_idx;
        values[left_idx] = left_val;
      } else {
        indices[left_idx] = right_idx;
        values[left_idx] = right_val;
      }
    }
  }

  __syncthreads();

  int min_val = values[0];
  int i = indices[0]/n;
  int j = indices[0]%n;

  // Always i should be smaller than j
  // That is cluster with higher index gets merged to the cluster with lower index
  if (i > j) {
    int temp = i;
    i = j;
    j = temp;
  } 

  entry[0] = i;
  entry[1] = j;
  entry[2] = min_val;
}

// This is a multi block parralell reduction
// reduce in block_mins after kernel finishes
__global__ void min_reduction(float *arr, float* block_mins, int n)
{
  int index = threadIdx.x + blockIdx.x * blockDim.x;
  int next = 1, left, right;
  n /= 2;
  while (n > 0){
    if (index < n){
      left = index * next * 2;
      right = left + next;
      if (arr[left] < arr[right]){
        arr[left] = arr[right];
      }
    }
    next *= 2;
    n /= 2;
  }
  __syncthreads();
  if (threadIdx.x == 0)
    block_mins[blockIdx.x] = arr[0];
}
