#pragma once
#include "AddNumkernel.cuh"

#include <iostream>

using namespace std;

#define DX 100

class CTest {
public:
  int *a;
  int *b;
  int *c;

  void setParameter();
  void addNum();
  void show();
  void evolution();
};
