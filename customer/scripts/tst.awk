{
	printf("%s\n", $0)
  n = split($0, arr, ",")
	for (i = 1; i <= n; ++i) {
		printf("arr[%d] = %s\n", i, arr[i])
	}
}
