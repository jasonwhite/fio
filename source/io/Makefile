default: all

.PHONY: all run
all: unittest

DMD = dmd

buffered.o: stream.o
text.o: stream.o
stdio.o: stream.o file.o buffered.o text.o
array.o: stream.o

%.o: %.d
	$(DMD) -unittest -I.. -cov -of$@ -c $^

unittest: file.o stream.o buffered.o text.o stdio.o array.o locking.o
	$(DMD) -main -of$@ $^

run: unittest
	./unittest

.PHONY: clean
clean:
	$(RM) *.lst *.o .deleteme* unittest
