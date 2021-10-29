package main

import "fmt"

type Book struct{
	// defining struct variables
	name string
	author string
	pages int
}

// function to print book details
func (book Book) print_details(){

	fmt.Printf("Book %s was written by %s.", book.name, book.author)
	fmt.Printf("\nIt contains %d pages.\n", book.pages)
}