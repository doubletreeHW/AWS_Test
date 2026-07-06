package com.example.test.service;

import com.example.test.model.BlogPost;
import org.springframework.stereotype.Service;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.concurrent.atomic.AtomicLong;

@Service
public class BlogService {

    private final List<BlogPost> posts = new CopyOnWriteArrayList<>();
    private final AtomicLong idGenerator = new AtomicLong(1);

    public BlogService() {
        // Seed with sample data
        createPost("첫 번째 블로그 포스트", "안녕하세요! 새롭게 구축된 스프링 부트 블로그입니다. 여기에 다양한 개발 일지와 생각을 자유롭게 작성해 보세요.", "관리자");
        createPost("AWS 배포 가이드", "이 블로그 애플리케이션은 간단하고 가볍게 작성되어 AWS App Runner, Elastic Beanstalk 또는 EC2 환경에 매우 쉽게 빌드하여 배포할 수 있습니다.", "데브옵스");
    }

    public List<BlogPost> getAllPosts() {
        // Return posts sorted by creation date descending
        List<BlogPost> sorted = new ArrayList<>(posts);
        sorted.sort((a, b) -> b.getCreatedAt().compareTo(a.getCreatedAt()));
        return sorted;
    }

    public Optional<BlogPost> getPostById(Long id) {
        return posts.stream().filter(post -> post.getId().equals(id)).findFirst();
    }

    public BlogPost createPost(String title, String content, String author) {
        BlogPost post = BlogPost.builder()
                .id(idGenerator.getAndIncrement())
                .title(title)
                .content(content)
                .author(author == null || author.trim().isEmpty() ? "익명" : author)
                .createdAt(LocalDateTime.now())
                .build();
        posts.add(post);
        return post;
    }

    public boolean deletePost(Long id) {
        return posts.removeIf(post -> post.getId().equals(id));
    }
}
