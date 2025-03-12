#include <iostream>



int main() {
  intptr_t _addr = 0;

  {
    int* d = new int(1);

    _addr = reinterpret_cast<intptr_t>(d);

    delete d;
  }


  {
    std::cout << _addr << std::endl;

    int* d = reinterpret_cast<int*>(_addr);


    std::cout << d << std::endl;

    // Invalid read of size x
    std::cout << (*d) << std::endl;
  }

  return 0;
}
