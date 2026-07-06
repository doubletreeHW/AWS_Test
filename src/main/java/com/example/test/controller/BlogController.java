package com.example.test.controller;

import com.example.test.model.BlogPost;
import com.example.test.service.BlogService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.web.bind.annotation.*;

import java.util.Optional;

@Controller
public class BlogController {

    private final BlogService blogService;

    @Autowired
    public BlogController(BlogService blogService) {
        this.blogService = blogService;
    }

    @GetMapping("/")
    public String listPosts(Model model) {
        model.addAttribute("posts", blogService.getAllPosts());
        return "blog/list";
    }

    @GetMapping("/posts/{id}")
    public String viewPost(@PathVariable("id") Long id, Model model) {
        Optional<BlogPost> post = blogService.getPostById(id);
        if (post.isPresent()) {
            model.addAttribute("post", post.get());
            return "blog/view";
        }
        return "redirect:/";
    }

    @GetMapping("/posts/new")
    public String showCreateForm(Model model) {
        return "blog/form";
    }

    @PostMapping("/posts")
    public String createPost(
            @RequestParam("title") String title,
            @RequestParam("content") String content,
            @RequestParam(value = "author", required = false) String author) {
        blogService.createPost(title, content, author);
        return "redirect:/";
    }

    @PostMapping("/posts/{id}/delete")
    public String deletePost(@PathVariable("id") Long id) {
        blogService.deletePost(id);
        return "redirect:/";
    }
}
